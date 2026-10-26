import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// Configurable global shortcuts; monitor movement retains its existing fixed keys.
@MainActor
final class KeyboardController {
    private(set) var failures: [(action: ShortcutAction, chord: ShortcutChord, status: OSStatus)] = []
    private var observers: [NSObjectProtocol] = []
    private var suspended = false

    private let flyouts: FlyoutController
    private let assist: SnapAssistController
    private let zoneOverlay: ZoneOverlay
    private let workspaces: WorkspaceController

    init(flyouts: FlyoutController, assist: SnapAssistController, zoneOverlay: ZoneOverlay, workspaces: WorkspaceController) {
        self.flyouts = flyouts
        self.assist = assist
        self.zoneOverlay = zoneOverlay
        self.workspaces = workspaces
    }

    func start() {
        guard observers.isEmpty else { return }
        for name in [Settings.shortcutsDidChange, ShortcutLabels.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.registerShortcuts() }
            })
        }
        ShortcutLabels.start()
        registerShortcuts()
    }

    /// Temporarily release global keys so the recorder can receive existing shortcuts.
    func suspend(_ value: Bool) {
        suspended = value
        registerShortcuts()
    }

    private func registerShortcuts() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        guard !suspended else { return }
        failures.removeAll()
        let settings = Settings.shortcuts
        let flyoutKey = ShortcutLabels.flyoutKey
        for action in ShortcutAction.allCases {
            for (index, chord) in settings.chords(for: action, flyoutKey: flyoutKey).enumerated() {
                let status = center.register(keyCode: chord.keyCode, modifiers: chord.modifiers.rawValue) { [weak self] in
                    self?.perform(action, index: index)
                }
                if status != noErr { failures.append((action, chord, status)) }
            }
        }
    }

    private func perform(_ action: ShortcutAction, index: Int) {
        switch action {
        case .left: snap(.left)
        case .right: snap(.right)
        case .up: snap(.up)
        case .down: snap(.down)
        case .flyout: showFlyout()
        case .layouts: activateLayout(index)
        case .workspaces: restoreWorkspace(index)
        case .monitorLeft: move(.left)
        case .monitorRight: move(.right)
        case .monitorUp: move(.up)
        case .monitorDown: move(.down)
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

    private func move(_ direction: SnapDirection) {
        guard let window = AXWindow.focused(), !window.isAppExcluded, window.isStandard, !window.isFullScreen,
              let frame = window.frame, let screen = Screens.screen(for: frame),
              let next = Screens.neighbor(of: screen, direction: direction) else { return NSSound.beep() }
        flyouts.hide()
        assist.dismiss()
        SnapEngine.shared.move(window, from: screen, to: next)
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
