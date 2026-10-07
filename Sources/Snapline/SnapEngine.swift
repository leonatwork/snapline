import AppKit
import SnaplineCore

/// Moves windows into zones and remembers their pre-snap frame so they can be
/// restored (Win+Down, or dragging a snapped window away).
@MainActor
final class SnapEngine {
    static let shared = SnapEngine()

    struct Record {
        var restore: CGRect
        var snapped: CGRect
    }

    private var records: [WindowKey: Record] = [:]

    func frame(for zone: Zone, on screen: NSScreen) -> CGRect {
        FrameCalculator.frame(for: zone, in: screen.axVisibleFrame, gap: Settings.gap)
    }

    func snap(_ window: AXWindow, to zone: Zone, on screen: NSScreen) {
        snap(window, to: frame(for: zone, on: screen))
    }

    func snap(_ window: AXWindow, to target: CGRect) {
        guard let current = window.frame else { return }
        let key = WindowKey(window)

        // Keep the original frame across consecutive snaps (thirds → half → …)
        // as long as the window is still where we last put it.
        let restore: CGRect
        if let rec = records[key], rec.snapped.isRoughlyEqual(to: current) {
            restore = rec.restore
        } else {
            restore = current
        }

        window.setFrame(target)
        records[key] = Record(restore: restore, snapped: window.frame ?? target)
        pruneIfNeeded()
    }

    /// Returns false if the window was not snapped by us.
    @discardableResult
    func restore(_ window: AXWindow) -> Bool {
        let key = WindowKey(window)
        guard let rec = records.removeValue(forKey: key) else { return false }
        window.setFrame(rec.restore)
        return true
    }

    /// The record if the window is still sitting in its snapped frame.
    func snappedRecord(for window: AXWindow, currentFrame: CGRect) -> Record? {
        guard let rec = records[WindowKey(window)], rec.snapped.isRoughlyEqual(to: currentFrame) else { return nil }
        return rec
    }

    func forget(_ window: AXWindow) {
        records.removeValue(forKey: WindowKey(window))
    }

    private func pruneIfNeeded() {
        guard records.count > 200 else { return }
        records = records.filter { $0.key.element.frame != nil }
    }
}

extension CGRect {
    func isRoughlyEqual(to other: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
