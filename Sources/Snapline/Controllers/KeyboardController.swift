import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// Win + Arrow equivalents on ⌃⌥ + Arrow, plus ⌃⌥Z for the layouts flyout (Win + Z).
@MainActor
final class KeyboardController {
    static let modifiers = controlKey | optionKey

    private let flyouts: FlyoutController
    private let assist: SnapAssistController

    init(flyouts: FlyoutController, assist: SnapAssistController) {
        self.flyouts = flyouts
        self.assist = assist
    }

    func start() {
        let hk = HotKeyCenter.shared
        let mods = Self.modifiers
        hk.register(keyCode: kVK_LeftArrow, modifiers: mods) { [weak self] in self?.snap(.left) }
        hk.register(keyCode: kVK_RightArrow, modifiers: mods) { [weak self] in self?.snap(.right) }
        hk.register(keyCode: kVK_UpArrow, modifiers: mods) { [weak self] in self?.snap(.up) }
        hk.register(keyCode: kVK_DownArrow, modifiers: mods) { [weak self] in self?.snap(.down) }
        hk.register(keyCode: kVK_ANSI_Z, modifiers: mods) { [weak self] in self?.showFlyout() }
        // ⌃⌥Y as well: on German keyboards Z and Y swap places.
        hk.register(keyCode: kVK_ANSI_Y, modifiers: mods) { [weak self] in self?.showFlyout() }
    }

    func showFlyout() {
        guard let window = AXWindow.focused(), window.isStandard, !window.isFullScreen,
              let frame = window.frame else { return NSSound.beep() }
        let anchor = window.zoomButton?.frame
            ?? CGRect(x: frame.minX + 60, y: frame.minY + 4, width: 16, height: 16)
        flyouts.show(for: window, anchorAX: anchor, mode: .hotkey)
    }

    private func snap(_ direction: SnapDirection) {
        guard let window = AXWindow.focused(), window.isStandard, !window.isFullScreen,
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
