import AppKit
import CoreGraphics

/// A session-level tap that sees mouse moves, keys and scrolling before the app
/// under the cursor does – the same approach Tappi uses for its switcher.
///
/// Snapline swallows events in two situations only:
/// - mouse moves over a window's green button, so macOS never opens its own
///   tiling menu there (the app simply never learns the cursor arrived);
/// - Tab, 1–9, Esc and the scroll wheel while a window is dragged with ⌥, to
///   switch layouts on the fly.
///
/// The callback runs on the main run loop and must stay fast: if it stalls,
/// macOS disables the tap.
@MainActor
final class EventTap {
    /// Return true to swallow the event.
    var onMouseMoved: ((CGPoint) -> Bool)?
    var onKeyDown: ((Int64, CGEventFlags) -> Bool)?
    var onScroll: ((Double) -> Bool)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isInstalled: Bool { tap != nil }

    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.mouseMoved, .keyDown, .scrollWheel, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
            },
            userInfo: refcon
        ) else {
            NSLog("Snapline: could not create event tap (Accessibility missing?)")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that took too long; just switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let swallow: Bool
        switch type {
        case .mouseMoved:
            // CG event locations use the same top-left origin as AX.
            swallow = onMouseMoved?(event.location) ?? false
        case .keyDown:
            swallow = onKeyDown?(event.getIntegerValueField(.keyboardEventKeycode), event.flags) ?? false
        case .scrollWheel:
            let delta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            swallow = onScroll?(delta) ?? false
        case .flagsChanged:
            onFlagsChanged?(event.flags)
            swallow = false
        default:
            swallow = false
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
    }
}
