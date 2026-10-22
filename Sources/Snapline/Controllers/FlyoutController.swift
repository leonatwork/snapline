import AppKit
import SnaplineCore

/// Owns the single Snap Layouts flyout and decides what a pick does.
@MainActor
final class FlyoutController {
    enum Mode { case hover, hotkey, drag }

    let flyout = LayoutFlyout()
    private let assist: SnapAssistController
    private(set) var mode: Mode?
    private var target: AXWindow?
    private var screen: NSScreen?
    private var outsideClickMonitor: Any?

    private var store: LayoutStore { .shared }

    init(assist: SnapAssistController) {
        self.assist = assist
        flyout.grid.onPick = { [weak self] pick in self?.commit(pick) }
        flyout.onCancel = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { flyout.isVisible }
    var frame: NSRect { flyout.frame }

    /// Hover / hotkey: show the flyout for a specific window, anchored below `anchor`.
    func show(for window: AXWindow, anchorAX anchor: CGRect, mode: Mode) {
        guard !window.isAppExcluded, let frame = window.frame, let screen = Screens.screen(for: frame) else { return }
        target = window
        self.screen = screen
        self.mode = mode
        assist.dismiss()

        let topLeft = Screens.toCocoa(CGPoint(x: anchor.minX - 12, y: anchor.maxY + 6))
        flyout.present(layouts: store.layouts(for: screen), activeIndex: store.activeLayoutIndex(for: screen),
                       screen: screen, anchor: topLeft, interactive: true, numbered: mode == .hotkey)
        if mode == .hotkey {
            flyout.makeKey()
            installOutsideClickMonitor()
        }
    }

    /// Drag: show the snap bar at the top center of the screen under the cursor.
    func showSnapBar(on screen: NSScreen) {
        if mode == .drag, self.screen == screen, isVisible { return }
        self.screen = screen
        mode = .drag
        target = nil
        flyout.present(layouts: store.layouts(for: screen), activeIndex: nil, screen: screen,
                       anchor: NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 8),
                       centered: true, interactive: false)
    }

    func pickDuringDrag(atCocoa point: NSPoint) -> LayoutPick? {
        guard mode == .drag, isVisible else { return nil }
        return flyout.pick(atCocoa: point)
    }

    var dragScreen: NSScreen? { mode == .drag ? screen : nil }

    func hide() {
        flyout.dismiss()
        mode = nil
        target = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func installOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func commit(_ pick: LayoutPick) {
        guard let target, let screen else { return }
        hide()
        guard !target.isAppExcluded else { return }
        SnapEngine.shared.snap(target, to: pick.zone, on: screen)
        target.focus()
        if Settings.snapAssist {
            assist.show(layout: pick.layout, filled: pick.zoneIndex, on: screen, placed: target)
        }
    }
}
