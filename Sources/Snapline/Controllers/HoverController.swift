import AppKit

/// Knows where every visible window's green button is, so the event tap can tell
/// in microseconds whether the cursor is on one.
///
/// Built from `CGWindowList` (z-order and bounds, cheap) plus one AX lookup per
/// window – repeated only when that window moved or resized.
@MainActor
final class GreenButtonIndex {
    struct Entry {
        let windowNumber: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let button: CGRect?
    }

    /// On-screen windows, front to back.
    private(set) var entries: [Entry] = []
    private var cache: [CGWindowID: (bounds: CGRect, button: CGRect?)] = [:]
    private var refreshedAt: CFTimeInterval = 0
    private var refreshScheduled = false

    /// Refreshes on the next run loop pass if the snapshot is older than `maxAge`.
    /// Never blocks the caller – the event tap must stay fast.
    func refreshSoon(maxAge: CFTimeInterval = 0.12) {
        guard !refreshScheduled, CACurrentMediaTime() - refreshedAt > maxAge else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refresh()
            }
        }
    }

    func refresh() {
        refreshedAt = CACurrentMediaTime()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        let ownPid = getpid()

        var next: [Entry] = []
        var seen = Set<CGWindowID>()
        for item in info {
            guard (item[kCGWindowLayer as String] as? Int) == 0,
                  let number = item[kCGWindowNumber as String] as? CGWindowID,
                  let pid = item[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
                  let dict = item[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict)
            else { continue }
            seen.insert(number)

            let button: CGRect?
            if let cached = cache[number], cached.bounds == bounds {
                button = cached.button
            } else {
                button = Self.lookUpButton(pid: pid, bounds: bounds)
                cache[number] = (bounds, button)
            }
            next.append(Entry(windowNumber: number, pid: pid, bounds: bounds, button: button))
        }
        cache = cache.filter { seen.contains($0.key) }
        entries = next
    }

    /// The window whose green button is under `point` – only if that window is the
    /// frontmost one there, so a button hidden behind another window never counts.
    func hit(_ point: CGPoint) -> Entry? {
        guard let front = entries.first(where: { $0.bounds.contains(point) }),
              let button = front.button, button.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        return front
    }

    func window(for entry: Entry) -> AXWindow? {
        AXWindow.windows(of: entry.pid).first { $0.frame.map { $0.isRoughlyEqual(to: entry.bounds, tolerance: 2) } ?? false }
    }

    private static func lookUpButton(pid: pid_t, bounds: CGRect) -> CGRect? {
        guard let window = AXWindow.windows(of: pid).first(where: {
            $0.frame.map { $0.isRoughlyEqual(to: bounds, tolerance: 2) } ?? false
        }), window.isStandard else { return nil }
        return window.zoomButton?.frame
    }
}

/// Shows the Snap Layouts flyout while the cursor rests on a window's green button,
/// like hovering the maximize button on Windows 11 – and keeps macOS' own tiling
/// menu from appearing there.
@MainActor
final class HoverController {
    private let flyouts: FlyoutController
    let index = GreenButtonIndex()
    private var dwellTimer: Timer?
    private var hideTimer: Timer?
    private var hovered: CGWindowID?
    private var buttonFrameAX: CGRect?

    /// Rest time on the button before the flyout opens. Short, because the macOS
    /// menu no longer competes for the spot.
    private let dwell: TimeInterval = 0.15
    /// Grace period when the cursor leaves button and flyout.
    private let grace: TimeInterval = 0.3

    init(flyouts: FlyoutController) {
        self.flyouts = flyouts
    }

    func start(tap: EventTap) {
        index.refresh()
        // The session tap also sees moves over our own flyout, so this one hook
        // covers both the button and the hide logic.
        tap.onMouseMoved = { [weak self] point in self?.mouseMoved(to: point) ?? false }
    }

    /// Called from the event tap for every mouse move. Returns true to swallow it.
    private func mouseMoved(to point: CGPoint) -> Bool {
        index.refreshSoon()
        let hit = index.hit(point)

        if flyouts.isVisible, flyouts.mode == .hover {
            updateHideTimer(cursor: Screens.toCocoa(point))
        } else if let hit, Settings.hoverFlyout {
            if hovered != hit.windowNumber {
                hovered = hit.windowNumber
                dwellTimer?.invalidate()
                dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.open(hit) }
                }
            }
        } else if hovered != nil {
            hovered = nil
            dwellTimer?.invalidate()
        }

        return hit != nil && Settings.suppressNativeMenu
    }

    private func open(_ entry: GreenButtonIndex.Entry) {
        guard hovered == entry.windowNumber, !flyouts.isVisible, NSEvent.pressedMouseButtons == 0,
              let button = entry.button, let window = index.window(for: entry), !window.isFullScreen
        else { return }
        buttonFrameAX = button
        flyouts.show(for: window, anchorAX: button, mode: .hover)
    }

    private func updateHideTimer(cursor: NSPoint) {
        if keepsFlyoutOpen(cursor) {
            hideTimer?.invalidate()
            hideTimer = nil
        } else if hideTimer == nil {
            hideTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hideTimer = nil
                    if self.flyouts.mode == .hover, !self.keepsFlyoutOpen(NSEvent.mouseLocation) {
                        self.flyouts.hide()
                        self.buttonFrameAX = nil
                        self.hovered = nil
                    }
                }
            }
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
}
