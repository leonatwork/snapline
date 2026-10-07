import AppKit

/// Shows the Snap Layouts flyout while the cursor rests on a window's green button,
/// like hovering the maximize button on Windows 11.
@MainActor
final class HoverController {
    private let flyouts: FlyoutController
    private var monitors: [Any] = []
    private var dwellTimer: Timer?
    private var hideTimer: Timer?
    private var buttonFrameAX: CGRect?

    /// Rest time on the button before the flyout opens.
    private let dwell: TimeInterval = 0.25
    /// Grace period when the cursor leaves button and flyout.
    private let grace: TimeInterval = 0.3

    init(flyouts: FlyoutController) {
        self.flyouts = flyouts
    }

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { monitors.append(m) }
        // Events over our own flyout are delivered locally.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { handler($0); return $0 }) {
            monitors.append(m)
        }
    }

    private func mouseMoved() {
        guard Settings.hoverFlyout else { return }
        let cursor = NSEvent.mouseLocation

        if flyouts.isVisible, flyouts.mode == .hover {
            if keepsFlyoutOpen(cursor) {
                hideTimer?.invalidate()
                hideTimer = nil
            } else if hideTimer == nil {
                hideTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.hideTimer = nil
                        if !self.keepsFlyoutOpen(NSEvent.mouseLocation) {
                            self.flyouts.hide()
                            self.buttonFrameAX = nil
                        }
                    }
                }
            }
            return
        }

        // Debounce: only query accessibility once the cursor comes to rest.
        dwellTimer?.invalidate()
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkUnderCursor() }
        }
    }

    private func keepsFlyoutOpen(_ cursor: NSPoint) -> Bool {
        let flyoutFrame = flyouts.frame.insetBy(dx: -12, dy: -12)
        if flyoutFrame.contains(cursor) { return true }
        guard let button = buttonFrameAX else { return false }
        let buttonFrame = Screens.toCocoa(button).insetBy(dx: -6, dy: -6)
        if buttonFrame.contains(cursor) { return true }
        // The corridor between the button and the flyout below it.
        let corridor = NSRect(x: min(buttonFrame.minX, flyoutFrame.minX), y: flyoutFrame.maxY,
                              width: buttonFrame.maxX + 40 - min(buttonFrame.minX, flyoutFrame.minX),
                              height: max(buttonFrame.maxY - flyoutFrame.maxY, 0))
        return corridor.contains(cursor)
    }

    private func checkUnderCursor() {
        guard Settings.hoverFlyout, !flyouts.isVisible,
              NSEvent.pressedMouseButtons == 0,
              let element = AXWindow.element(at: Screens.cursorAX),
              let subrole = element.subrole,
              subrole == kAXFullScreenButtonSubrole || subrole == kAXZoomButtonSubrole,
              let buttonFrame = element.frame,
              let window = AXWindow.window(containing: element),
              !window.isOwnWindow, !window.isFullScreen
        else { return }

        buttonFrameAX = buttonFrame
        flyouts.show(for: window, anchorAX: buttonFrame, mode: .hover)
    }
}
