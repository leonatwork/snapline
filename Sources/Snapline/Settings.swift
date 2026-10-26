import AppKit
import ServiceManagement
import SnaplineCore

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let dragSnap = "dragSnap"
        static let hoverFlyout = "hoverFlyout"
        static let snapAssist = "snapAssist"
        static let restoreOnDrag = "restoreOnDrag"
        static let gap = "gap"
        static let superWideColumns = "superWideColumns"
        static let optionDragZones = "optionDragZones"
        static let suppressNativeMenu = "suppressNativeMenu"
        static let livePreviews = "livePreviews"
        static let launchAppsForWorkspaces = "launchAppsForWorkspaces"
        static let zoneModifier = "zoneModifier"
        static let debugLog = "debugLog"
        static let excludedApps = "excludedApps"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.dragSnap: true,
            Key.hoverFlyout: true,
            Key.snapAssist: true,
            Key.restoreOnDrag: true,
            Key.gap: 0.0,
            Key.superWideColumns: 3,
            Key.optionDragZones: true,
            Key.suppressNativeMenu: true,
            Key.livePreviews: true,
            Key.launchAppsForWorkspaces: true,
            Key.zoneModifier: ZoneModifier.command.rawValue,
            Key.debugLog: false,
            Key.excludedApps: [String](),
        ])
    }

    /// Persisted bundle IDs, with no default exclusions.
    static var appExclusions: AppExclusions {
        get { AppExclusions(bundleIDs: defaults.stringArray(forKey: Key.excludedApps) ?? []) }
        set { defaults.set(newValue.bundleIDs, forKey: Key.excludedApps) }
    }

    static func isAppExcluded(pid: pid_t) -> Bool {
        let exclusions = appExclusions
        guard !exclusions.bundleIDs.isEmpty else { return false }
        return exclusions.contains(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
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

    /// Hold ⌥ while dragging a window to drop it into the zones of the active layout.
    static var optionDragZones: Bool {
        get { defaults.bool(forKey: Key.optionDragZones) }
        set { defaults.set(newValue, forKey: Key.optionDragZones) }
    }

    /// Key held while dragging to drop into zones.
    static var zoneModifier: ZoneModifier {
        get { ZoneModifier(rawValue: defaults.string(forKey: Key.zoneModifier) ?? "") ?? .command }
        set { defaults.set(newValue.rawValue, forKey: Key.zoneModifier) }
    }

    /// `defaults write io.github.leonatwork.snapline debugLog -bool true`, then
    /// `tail -f ~/Library/Logs/Snapline/debug.log`.
    static var debugLog: Bool { defaults.bool(forKey: Key.debugLog) }

    /// Keep macOS' own tiling menu on the green button from appearing.
    static var suppressNativeMenu: Bool {
        get { defaults.bool(forKey: Key.suppressNativeMenu) }
        set { defaults.set(newValue, forKey: Key.suppressNativeMenu) }
    }

    /// Live window thumbnails in Snap Assist (needs Screen Recording).
    static var livePreviews: Bool {
        get { defaults.bool(forKey: Key.livePreviews) }
        set { defaults.set(newValue, forKey: Key.livePreviews) }
    }

    /// Start apps that are missing when restoring a workspace.
    static var launchAppsForWorkspaces: Bool {
        get { defaults.bool(forKey: Key.launchAppsForWorkspaces) }
        set { defaults.set(newValue, forKey: Key.launchAppsForWorkspaces) }
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

/// Which key turns a window drag into a drop into zones (FancyZones uses ⇧).
enum ZoneModifier: String, CaseIterable {
    case command, option, shift

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .shift: return .shift
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }

    /// Spanning several zones needs a second key; ⇧ unless that is already taken.
    var spanFlag: NSEvent.ModifierFlags { self == .shift ? .option : .shift }
    var spanSymbol: String { self == .shift ? "⌥" : "⇧" }
}

/// Diagnostics go to a plain file: the unified log redacts NSLog text as <private>.
func debugLog(_ message: @autoclosure () -> String) {
    guard Settings.debugLog else { return }
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Snapline")
    let url = dir.appendingPathComponent("debug.log")
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withFractionalSeconds])
    guard let data = "\(stamp) \(message())\n".data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url)
    }
}

/// Stage Manager and built-in macOS tiling can interfere with snapping.
enum NativeTiling {
    private static let domain = "com.apple.WindowManager" as CFString

    private static func read(_ key: String) -> Bool? {
        CFPreferencesCopyValue(key as CFString, domain,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
    }

    /// Refresh the external domain each time the menu opens, including changes
    /// made in Control Center/System Settings while Snapline is running.
    static var snapshot: WindowManagerSettings {
        _ = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return WindowManagerSettings(
            stageManagerEnabled: read("GloballyEnabled"),
            edgeDragEnabled: read("EnableTilingByEdgeDrag"),
            topEdgeDragEnabled: read("EnableTopTilingByEdgeDrag"),
            optionDragEnabled: read("EnableTilingOptionAccelerator"))
    }

    static var stageManagerEnabled: Bool { snapshot.stageManagerEnabled }

    /// Write individual allowlisted keys, never replace the foreign domain.
    /// A successful read-back does not guarantee WindowManager applied them yet.
    static func disableTiling(confirmed: Bool) -> Bool {
        guard confirmed else { return false }
        WindowManagerSettings.disableTiling(confirmed: confirmed) { key, value in
            CFPreferencesSetValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, domain,
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        let saved = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return saved && WindowManagerSettings.tilingKeys.allSatisfy { read($0) == false }
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
