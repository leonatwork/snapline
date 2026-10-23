import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// Registers the persisted shortcuts and replaces them when settings or input sources change.
@MainActor
final class KeyboardController: NSObject {
    struct RegistrationFailure {
        let action: ShortcutAction
        let shortcut: Shortcut
        let status: OSStatus
    }
    private(set) var registrationFailures: [RegistrationFailure] = []
    private var recording = false
    static let recordingDidChange = Notification.Name("Snapline.shortcutRecordingDidChange")

    private let flyouts: FlyoutController
    private let assist: SnapAssistController
    private let zoneOverlay: ZoneOverlay
    private let workspaces: WorkspaceController

    init(flyouts: FlyoutController, assist: SnapAssistController, zoneOverlay: ZoneOverlay, workspaces: WorkspaceController) {
        self.flyouts = flyouts
        self.assist = assist
        self.zoneOverlay = zoneOverlay
        self.workspaces = workspaces
        super.init()
    }

    func start() {
        _ = ShortcutDisplay.shared
        NotificationCenter.default.addObserver(self, selector: #selector(reloadShortcuts), name: Settings.shortcutsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadShortcuts), name: ShortcutDisplay.inputSourceDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recordingChanged(_:)), name: Self.recordingDidChange, object: nil)
        reloadShortcuts()
    }

    @objc private func recordingChanged(_ notification: Notification) {
        recording = notification.object as? Bool ?? false
        reloadShortcuts()
    }

    @objc private func reloadShortcuts() {
        let hk = HotKeyCenter.shared
        let removalStatus = hk.unregisterAll()
        registrationFailures.removeAll()
        let display = ShortcutDisplay.shared
        var registered: Set<Shortcut> = []
        for action in ShortcutAction.allCases {
            for (index, shortcut) in display.shortcuts(for: action).enumerated() {
                // Failed unregistration is visible too; never activate overlapping old/new keys.
                let status: OSStatus
                if removalStatus != noErr { status = removalStatus }
                else if recording { continue }
                else if registered.contains(shortcut) { status = OSStatus(eventHotKeyExistsErr) }
                else if shortcut.keyCode >= 128 || shortcut.modifiers.isEmpty || !shortcut.modifiers.subtracting(.all).isEmpty {
                    status = OSStatus(paramErr)
                }
                else {
                    status = hk.register(keyCode: Int(shortcut.keyCode), modifiers: shortcut.modifiers.carbon) { [weak self] in
                        switch action {
                        case .left: self?.snap(.left)
                        case .right: self?.snap(.right)
                        case .up: self?.snap(.up)
                        case .down: self?.snap(.down)
                        case .flyout: self?.showFlyout()
                        case .layouts: self?.activateLayout(index)
                        case .workspaces: self?.restoreWorkspace(index)
                        }
                    }
                    if status == noErr { registered.insert(shortcut) }
                }
                if status != noErr {
                    registrationFailures.append(RegistrationFailure(action: action, shortcut: shortcut, status: status))
                }
            }
        }
    }

    /// The monitor a shortcut applies to: the focused window's, else the cursor's.
    private var targetScreen: NSScreen? {
        if let frame = AXWindow.focused()?.frame, let screen = Screens.screen(for: frame) { return screen }
        return Screens.screen(containingAX: Screens.cursorAX) ?? NSScreen.main
    }

    func activateLayout(_ index: Int) {
        guard let screen = targetScreen else { return }
        let layouts = LayoutStore.shared.layouts(for: screen)
        guard index < layouts.count else { return NSSound.beep() }
        LayoutStore.shared.setActiveLayout(layouts[index], for: screen)
        zoneOverlay.flash(layout: layouts[index], number: index + 1, count: layouts.count, on: screen)
    }

    private func restoreWorkspace(_ index: Int) {
        let all = LayoutStore.shared.workspaces
        guard index < all.count else { return NSSound.beep() }
        workspaces.restore(all[index])
    }

    func showFlyout() {
        guard let window = AXWindow.focused(), !window.isAppExcluded, window.isStandard, !window.isFullScreen,
              let frame = window.frame else { return NSSound.beep() }
        let anchor = window.zoomButton?.frame
            ?? CGRect(x: frame.minX + 60, y: frame.minY + 4, width: 16, height: 16)
        flyouts.show(for: window, anchorAX: anchor, mode: .hotkey)
    }

    private func snap(_ direction: SnapDirection) {
        guard let window = AXWindow.focused(), !window.isAppExcluded, window.isStandard, !window.isFullScreen,
              let frame = window.frame, let screen = Screens.screen(for: frame) else { return NSSound.beep() }
        flyouts.hide()
        assist.dismiss()

        let engine = SnapEngine.shared
        let placement = KeyboardSnap.placement(of: frame, in: screen.axVisibleFrame, gap: Settings.gap,
                                               columns: screen.snapColumns)
        switch KeyboardSnap.action(for: direction, from: placement, columns: screen.snapColumns) {
        case .zone(let zone):
            engine.snap(window, to: zone, on: screen)
        case .maximize:
            engine.snap(window, to: .full, on: screen)
        case .restore:
            if !engine.restore(window) {
                // Not snapped by us: fall back to a centered, comfortable size.
                let area = screen.axVisibleFrame
                let size = CGSize(width: min(area.width * 0.6, 1600), height: area.height * 0.75)
                window.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                       width: size.width, height: size.height))
            }
        case .minimize:
            window.minimize()
        case .adjacentScreen(let side, let part):
            guard let next = Screens.neighbor(of: screen, side: side) else { return }
            // Moving left lands in the neighbour's rightmost column and vice versa.
            let zone = KeyboardSnap.edgeColumn(side == .left ? .right : .left, part: part, columns: next.snapColumns)
            engine.snap(window, to: zone, on: next)
        }
    }
}
