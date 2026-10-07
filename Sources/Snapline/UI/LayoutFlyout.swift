import AppKit
import SnaplineCore

/// A zone inside one of the flyout's layout tiles.
struct LayoutPick: Equatable {
    let layout: Layout
    let zoneIndex: Int

    var zone: Zone { layout.zones[zoneIndex] }
}

/// The Windows 11 Snap Layouts popup: a grid of miniature layouts whose zones can be
/// clicked (hover/hotkey mode) or targeted with the cursor while dragging a window.
@MainActor
final class LayoutFlyout: NSPanel {
    let grid = LayoutGridView()
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.addSubview(grid)
        contentView = background
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Shows the flyout hanging below `anchor` (Cocoa coordinates) – either with its
    /// top-left corner there or horizontally centered on it – clamped to the screen.
    func present(layouts: [Layout], screen: NSScreen, anchor: NSPoint, centered: Bool = false, interactive: Bool) {
        grid.configure(layouts: layouts, screenClass: screen.screenClass, interactive: interactive)
        let size = grid.frame.size
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        var origin = NSPoint(x: centered ? anchor.x - size.width / 2 : anchor.x, y: anchor.y - size.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        setFrame(NSRect(origin: origin, size: size), display: true)
        grid.frame.origin = .zero
        ignoresMouseEvents = !interactive
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                animator().alphaValue = 1
            }
        }
    }

    func dismiss() {
        grid.highlighted = nil
        orderOut(nil)
    }

    /// Drag mode: the cursor never actually enters our window (the dragged window has
    /// the mouse), so hit-test the global cursor position ourselves.
    func pick(atCocoa point: NSPoint) -> LayoutPick? {
        let local = grid.convert(convertPoint(fromScreen: point), from: nil)
        let pick = grid.pick(at: local)
        grid.highlighted = pick
        return pick
    }
}

@MainActor
final class LayoutGridView: NSView {
    var onPick: ((LayoutPick) -> Void)?

    var highlighted: LayoutPick? {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }

    private var layouts: [Layout] = []
    private var tileRects: [CGRect] = []
    private var interactive = true
    private var trackingArea: NSTrackingArea?

    private let padding: CGFloat = 12
    private let spacing: CGFloat = 12
    private let zoneGap: CGFloat = 3

    override var isFlipped: Bool { true }

    func configure(layouts: [Layout], screenClass: ScreenClass, interactive: Bool) {
        self.layouts = layouts
        self.interactive = interactive
        highlighted = nil

        // Tiles share the screen's shape so 32:9 layouts look like 32:9.
        let aspect: CGFloat
        switch screenClass {
        case .portrait: aspect = 9.0 / 16
        case .standard: aspect = 16.0 / 10
        case .wide: aspect = 21.0 / 9
        case .superWide: aspect = 32.0 / 9
        }
        let tileWidth: CGFloat = min(max(56 * aspect, 44), 184)
        let tileHeight = (tileWidth / aspect).rounded()

        let columns = min(LayoutCatalog.flyoutColumns(for: screenClass), max(layouts.count, 1))
        let rows = Int((Double(layouts.count) / Double(columns)).rounded(.up))
        tileRects = layouts.indices.map { i in
            let c = i % columns, r = i / columns
            return CGRect(x: padding + CGFloat(c) * (tileWidth + spacing),
                          y: padding + CGFloat(r) * (tileHeight + spacing),
                          width: tileWidth, height: tileHeight)
        }
        let width = padding * 2 + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * spacing
        let height = padding * 2 + CGFloat(rows) * tileHeight + CGFloat(rows - 1) * spacing
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        needsDisplay = true
    }

    private func zoneRect(_ zone: Zone, in tile: CGRect) -> CGRect {
        CGRect(x: tile.minX + zone.x * tile.width, y: tile.minY + zone.y * tile.height,
               width: zone.width * tile.width, height: zone.height * tile.height)
            .insetBy(dx: zoneGap / 2, dy: zoneGap / 2)
    }

    func pick(at point: CGPoint) -> LayoutPick? {
        for (i, tile) in tileRects.enumerated() where tile.insetBy(dx: -spacing / 2, dy: -spacing / 2).contains(point) {
            let layout = layouts[i]
            // Nearest zone wins so the small gaps between zones don't flicker.
            let best = layout.zones.indices.min { a, b in
                zoneRect(layout.zones[a], in: tile).distance(to: point) < zoneRect(layout.zones[b], in: tile).distance(to: point)
            }
            if let best, zoneRect(layout.zones[best], in: tile).distance(to: point) < spacing / 2 {
                return LayoutPick(layout: layout, zoneIndex: best)
            }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let normal = NSColor.labelColor.withAlphaComponent(0.16)
        let border = NSColor.labelColor.withAlphaComponent(0.22)
        let accent = NSColor.controlAccentColor

        for (i, tile) in tileRects.enumerated() {
            let layout = layouts[i]
            for (z, zone) in layout.zones.enumerated() {
                let rect = zoneRect(zone, in: tile)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                let isHot = highlighted?.layout == layout && highlighted?.zoneIndex == z
                (isHot ? accent : normal).setFill()
                path.fill()
                (isHot ? accent : border).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    // MARK: Mouse (interactive mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        guard interactive else { return }
        highlighted = pick(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard interactive else { return }
        highlighted = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard interactive, let pick = pick(at: convert(event.locationInWindow, from: nil)) else { return }
        onPick?(pick)
    }
}

private extension CGRect {
    func distance(to p: CGPoint) -> CGFloat {
        let dx = max(minX - p.x, 0, p.x - maxX)
        let dy = max(minY - p.y, 0, p.y - maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
