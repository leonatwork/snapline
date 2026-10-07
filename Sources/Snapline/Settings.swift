import AppKit
import ServiceManagement

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let dragSnap = "dragSnap"
        static let hoverFlyout = "hoverFlyout"
        static let snapAssist = "snapAssist"
        static let restoreOnDrag = "restoreOnDrag"
        static let gap = "gap"
        static let superWideColumns = "superWideColumns"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.dragSnap: true,
            Key.hoverFlyout: true,
            Key.snapAssist: true,
            Key.restoreOnDrag: true,
            Key.gap: 8.0,
            Key.superWideColumns: 3,
        ])
    }

    /// Aero Snap: drag windows to screen edges.
    static var dragSnap: Bool {
        get { defaults.bool(forKey: Key.dragSnap) }
        set { defaults.set(newValue, forKey: Key.dragSnap) }
    }

    /// Snap Layouts flyout when hovering the green window button.
    static var hoverFlyout: Bool {
        get { defaults.bool(forKey: Key.hoverFlyout) }
        set { defaults.set(newValue, forKey: Key.hoverFlyout) }
    }

    /// Offer other windows for the remaining zones after snapping via a layout.
    static var snapAssist: Bool {
        get { defaults.bool(forKey: Key.snapAssist) }
        set { defaults.set(newValue, forKey: Key.snapAssist) }
    }

    /// Dragging a snapped window away restores its previous size.
    static var restoreOnDrag: Bool {
        get { defaults.bool(forKey: Key.restoreOnDrag) }
        set { defaults.set(newValue, forKey: Key.restoreOnDrag) }
    }

    /// Space between snapped windows and around the screen edge, in points.
    static var gap: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.gap)) }
        set { defaults.set(Double(newValue), forKey: Key.gap) }
    }

    /// Column count for edge/keyboard snapping on 32:9 displays (2, 3 or 4).
    static var superWideColumns: Int {
        get { defaults.integer(forKey: Key.superWideColumns) }
        set { defaults.set(newValue, forKey: Key.superWideColumns) }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Snapline: launch at login failed: \(error)")
            }
        }
    }
}

/// The built-in macOS tiling (Sequoia and later) fights with our drag snapping.
enum NativeTiling {
    private static var domain: UserDefaults? { UserDefaults(suiteName: "com.apple.WindowManager") }

    /// "Drag windows to screen edges to tile" – on unless explicitly disabled.
    static var edgeDragEnabled: Bool {
        (domain?.object(forKey: "EnableTilingByEdgeDrag") as? Bool) ?? true
    }

    /// "Drag windows to menu bar to fill screen".
    static var topEdgeDragEnabled: Bool {
        (domain?.object(forKey: "EnableTopTilingByEdgeDrag") as? Bool) ?? true
    }

    static var conflicts: Bool { edgeDragEnabled || topEdgeDragEnabled }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
