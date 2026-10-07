import AppKit
import SnaplineCore

/// Canvas for editing a layout, shaped like the selected monitor.
///
/// - Click a zone: split it vertically at the cursor (⇧: horizontally)
/// - Drag a divider: resize; snaps to ¼, ⅓, ½, ⅔, ¾
/// - ⌥-click a zone: remove it
@MainActor
final class ZoneEditorView: NSView {
    var onChange: ((ZoneNode) -> Void)?

    private var tree: ZoneNode?
    private var staticZones: [Zone] = []
    private var editable = false
    private var aspect: CGFloat = 16.0 / 9
    private var screenSize = CGSize(width: 1920, height: 1080)

    private var hoverPoint: CGPoint?
    private var hoverDivider: ZoneNode.Divider?
    private var dragging: ZoneNode.Divider?
    private var trackingArea: NSTrackingArea?

    private let magnets: [CGFloat] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func show(tree: ZoneNode?, zones: [Zone], editable: Bool, screenSize: CGSize) {
        self.tree = tree
        staticZones = zones
        self.editable = editable && tree != nil
        self.screenSize = screenSize
        aspect = screenSize.width / max(screenSize.height, 1)
        hoverDivider = nil
        dragging = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private var zones: [Zone] { tree?.zones() ?? staticZones }

    /// The monitor-shaped area inside the view.
    private var canvas: CGRect {
        let area = bounds.insetBy(dx: 24, dy: 24)
        var size = CGSize(width: area.width, height: area.width / aspect)
        if size.height > area.height { size = CGSize(width: area.height * aspect, height: area.height) }
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func rect(for zone: Zone) -> CGRect {
        let c = canvas
        return CGRect(x: c.minX + zone.x * c.width, y: c.minY + zone.y * c.height,
                      width: zone.width * c.width, height: zone.height * c.height)
    }

    private func normalized(_ p: CGPoint) -> CGPoint {
        let c = canvas
        return CGPoint(x: (p.x - c.minX) / c.width, y: (p.y - c.minY) / c.height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let c = canvas
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: c.insetBy(dx: -6, dy: -6), xRadius: 10, yRadius: 10).fill()

        let accent = NSColor.controlAccentColor
        let removing = editable && NSEvent.modifierFlags.contains(.option)
        let hoveredZone = hoverPoint.flatMap { p in zones.firstIndex { rect(for: $0).contains(p) } }

        for (i, zone) in zones.enumerated() {
            let r = rect(for: zone).insetBy(dx: 3, dy: 3)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            let hot = editable && hoveredZone == i && hoverDivider == nil && dragging == nil
            let fill: NSColor = hot && removing ? .systemRed : accent
            fill.withAlphaComponent(hot ? 0.45 : 0.25).setFill()
            path.fill()
            fill.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.5
            path.stroke()

            drawCentered("\(i + 1)", in: r, size: min(40, r.height / 3), weight: .semibold, alpha: 0.9, offset: -10)
            let px = "\(Int((zone.width * screenSize.width).rounded())) × \(Int((zone.height * screenSize.height).rounded()))"
            let pct = "\(Int((zone.width * 100).rounded())) %"
            drawCentered("\(pct)  ·  \(px)", in: r, size: 11, weight: .regular, alpha: 0.7, offset: min(28, r.height / 4))
        }

        guard editable, let tree else { return }

        // Dividers.
        for divider in tree.dividers() {
            let line = lineRect(divider)
            let active = divider == dragging || divider == hoverDivider
            (active ? NSColor.white : NSColor.white.withAlphaComponent(0.35)).setFill()
            NSBezierPath(roundedRect: line, xRadius: 2, yRadius: 2).fill()
        }

        // Split preview.
        if dragging == nil, hoverDivider == nil, !removing, let p = hoverPoint, let i = hoveredZone {
            let r = rect(for: zones[i])
            let horizontal = NSEvent.modifierFlags.contains(.shift)
            let path = NSBezierPath()
            if horizontal {
                let y = snapped(normalized(p).y, within: zones[i].y, zones[i].maxY) * canvas.height + canvas.minY
                path.move(to: CGPoint(x: r.minX + 6, y: y))
                path.line(to: CGPoint(x: r.maxX - 6, y: y))
            } else {
                let x = snapped(normalized(p).x, within: zones[i].x, zones[i].maxX) * canvas.width + canvas.minX
                path.move(to: CGPoint(x: x, y: r.minY + 6))
                path.line(to: CGPoint(x: x, y: r.maxY - 6))
            }
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.setLineDash([6, 4], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func drawCentered(_ text: String, in r: CGRect, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, offset: CGFloat) {
        let s = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: max(size, 8), weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
        let sz = s.size()
        guard sz.width < r.width - 8 else { return }
        s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2 + offset))
    }

    private func lineRect(_ d: ZoneNode.Divider) -> CGRect {
        let c = canvas
        switch d.axis {
        case .columns:
            let x = c.minX + d.position * c.width
            return CGRect(x: x - 2, y: c.minY + d.area.y * c.height + 8, width: 4, height: d.area.height * c.height - 16)
        case .rows:
            let y = c.minY + d.position * c.height
            return CGRect(x: c.minX + d.area.x * c.width + 8, y: y - 2, width: d.area.width * c.width - 16, height: 4)
        }
    }

    private func divider(at p: CGPoint) -> ZoneNode.Divider? {
        guard let tree else { return nil }
        // Deepest divider first, so nested splits stay reachable.
        return tree.dividers().reversed().first { lineRect($0).insetBy(dx: -5, dy: -5).contains(p) }
    }

    /// Rounds to 0.5 % and pulls towards common fractions, clamped inside (lo, hi).
    private func snapped(_ value: CGFloat, within lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        var v = (value * 200).rounded() / 200
        if let magnet = magnets.first(where: { abs($0 - value) < 0.015 }) { v = magnet }
        let margin = (hi - lo) * ZoneNode.minRatio
        return min(max(v, lo + margin), hi - margin)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        hoverDivider = editable ? divider(at: hoverPoint!) : nil
        updateCursor()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        hoverDivider = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    private func updateCursor() {
        switch hoverDivider?.axis {
        case .columns: NSCursor.resizeLeftRight.set()
        case .rows: NSCursor.resizeUpDown.set()
        case nil: NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard editable, let tree else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let d = divider(at: p) {
            dragging = d
            return
        }
        guard let i = zones.firstIndex(where: { rect(for: $0).contains(p) }) else { return }
        let zone = zones[i]

        if event.modifierFlags.contains(.option) {
            commit(tree.removing(leaf: i))
        } else if event.modifierFlags.contains(.shift) {
            let y = snapped(normalized(p).y, within: zone.y, zone.maxY)
            commit(tree.splitting(leaf: i, axis: .rows, at: (y - zone.y) / zone.height))
        } else {
            let x = snapped(normalized(p).x, within: zone.x, zone.maxX)
            commit(tree.splitting(leaf: i, axis: .columns, at: (x - zone.x) / zone.width))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging, let tree else { return }
        let n = normalized(convert(event.locationInWindow, from: nil))
        let ratio: CGFloat
        switch d.axis {
        case .columns:
            ratio = (snapped(n.x, within: d.area.x, d.area.maxX) - d.area.x) / d.area.width
        case .rows:
            ratio = (snapped(n.y, within: d.area.y, d.area.maxY) - d.area.y) / d.area.height
        }
        let updated = tree.settingRatio(ratio, at: d.path)
        self.tree = updated
        // Keep following the same divider while its position changes.
        dragging = updated.dividers().first { $0.path == d.path }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil, let tree else { return }
        dragging = nil
        commit(tree)
    }

    private func commit(_ newTree: ZoneNode) {
        tree = newTree
        hoverDivider = nil
        needsDisplay = true
        onChange?(newTree)
    }
}
