import AppKit
import ApplicationServices

/// Thin wrapper around an accessibility window element. All geometry uses the AX
/// coordinate space: origin at the top-left of the primary display, y pointing down.
final class AXWindow {
    let element: AXUIElement
    let pid: pid_t

    init(_ element: AXUIElement) {
        self.element = element
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        self.pid = pid
    }

    static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        // Never let a hung app freeze our event handling.
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }()

    // MARK: Lookup

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        guard let win: AXUIElement = appEl.attribute(kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(win)
    }

    /// The element directly under an AX point, if any.
    static func element(at point: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &el) == .success
        else { return nil }
        return el
    }

    /// The window that owns the element under an AX point.
    static func window(at point: CGPoint) -> AXWindow? {
        guard let el = element(at: point) else { return nil }
        return window(containing: el)
    }

    static func window(containing element: AXUIElement) -> AXWindow? {
        if element.role == kAXWindowRole { return AXWindow(element) }
        if let win: AXUIElement = element.attribute(kAXWindowAttribute) { return AXWindow(win) }
        var current = element
        for _ in 0..<25 {
            guard let parent: AXUIElement = current.attribute(kAXParentAttribute) else { return nil }
            if parent.role == kAXWindowRole { return AXWindow(parent) }
            current = parent
        }
        return nil
    }

    /// All standard windows of an application.
    static func windows(of pid: pid_t) -> [AXWindow] {
        let appEl = AXUIElementCreateApplication(pid)
        let list: [AXUIElement] = appEl.attribute(kAXWindowsAttribute) ?? []
        return list.map(AXWindow.init)
    }

    // MARK: Attributes

    var title: String { element.attribute(kAXTitleAttribute) ?? "" }
    var subrole: String? { element.attribute(kAXSubroleAttribute) }
    var isStandard: Bool { subrole == kAXStandardWindowSubrole }
    var isMinimized: Bool { element.attribute(kAXMinimizedAttribute) ?? false }
    var isFullScreen: Bool { element.attribute("AXFullScreen") ?? false }
    var isOwnWindow: Bool { pid == getpid() }

    var zoomButton: AXUIElement? {
        element.attribute(kAXFullScreenButtonAttribute) ?? element.attribute(kAXZoomButtonAttribute)
    }

    var position: CGPoint? { element.pointAttribute(kAXPositionAttribute) }
    var size: CGSize? { element.sizeAttribute(kAXSizeAttribute) }

    var frame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    // MARK: Actions

    func setFrame(_ frame: CGRect) {
        let appEl = AXUIElementCreateApplication(pid)
        // Chromium/Electron animate every AX resize while this is on, which makes
        // snapping feel laggy. Turn it off for the duration of the change.
        let enhanced: Bool = appEl.attribute("AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer {
            if enhanced { AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }

        // Position first so the window lands on the target display, then size, then
        // position again in case the app clamped the origin while resizing.
        setPosition(frame.origin)
        setSize(frame.size)
        setPosition(frame.origin)
        if let s = size, abs(s.width - frame.width) > 1 || abs(s.height - frame.height) > 1 {
            setSize(frame.size)
        }
    }

    func setPosition(_ p: CGPoint) {
        var point = p
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
        }
    }

    func setSize(_ s: CGSize) {
        var size = s
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
        }
    }

    func minimize() {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    /// Brings the window to the front and activates its app.
    func focus() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

/// Hashable identity for a window, so we can remember per-window state.
struct WindowKey: Hashable {
    let element: AXUIElement

    init(_ window: AXWindow) { element = window.element }

    static func == (a: WindowKey, b: WindowKey) -> Bool { CFEqual(a.element, b.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var role: String? { attribute(kAXRoleAttribute) }
    var subrole: String? { attribute(kAXSubroleAttribute) }

    func pointAttribute(_ name: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    func sizeAttribute(_ name: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    var frame: CGRect? {
        guard let p = pointAttribute(kAXPositionAttribute), let s = sizeAttribute(kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }
}
