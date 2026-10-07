import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// A zone inside one of the flyout's layout tiles.
struct LayoutPick: Equatable {
    let layout: Layout
    let zoneIndex: Int

    var zone: Zone { layout.zones[zoneIndex] }
}

/// The Windows 11 Snap Layouts popup: a grid of miniature layouts whose zones can be
/// clicked (hover/hotkey mode) or targeted with the cursor while dragging a window.
/// Opened via hotkey it also takes digits like Win+Z: first the layout, then the zone.
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
        if grid.chosenLayout != nil {
            grid.chosenLayout = nil
        } else {
            onCancel?()
        }
    }

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5,
        kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

    override func keyDown(with event: NSEvent) {
        guard grid.showsNumbers, let digit = Self.digitKeys[Int(event.keyCode)] else {
            return super.keyDown(with: event)
        }
        grid.typeDigit(digit)
    }

    /// Shows the flyout hanging below `anchor` (Cocoa coordinates) – either with its
    /// top-left corner there or horizontally centered on it – clamped to the screen.
    func present(layouts: [Layout], activeIndex: Int?, screen: NSScreen, anchor: NSPoint,
                 centered: Bool = false, interactive: Bool, numbered: Bool = false) {
        grid.configure(layouts: layouts, activeIndex: activeIndex, screenClass: screen.screenClass,
                       interactive: interactive, numbered: numbered)
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
        grid.chosenLayout = nil
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

    /// Keyboard selection: the layout chosen with the first digit.
    var chosenLayout: Int? {
        didSet { needsDisplay = true }
    }

    private(set) var showsNumbers = false
    private var layouts: [Layout] = []
    private var activeIndex: Int?
    private var tileRects: [CGRect] = []
    private var interactive = true
    private var trackingArea: NSTrackingArea?

    private let padding: CGFloat = 12
    private let spacing: CGFloat = 12
    private let zoneGap: CGFloat = 3
    private let captionHeight: CGFloat = 16

    override var isFlipped: Bool { true }

    func configure(layouts: [Layout], activeIndex: Int?, screenClass: ScreenClass, interactive: Bool, numbered: Bool) {
        self.layouts = layouts
        self.activeIndex = activeIndex
        self.interactive = interactive
        showsNumbers = numbered
        highlighted = nil
        chosenLayout = nil

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
        let cellHeight = tileHeight + captionHeight

        let columns = min(LayoutCatalog.flyoutColumns(for: screenClass), max(layouts.count, 1))
        let rows = Int((Double(layouts.count) / Double(columns)).rounded(.up))
        tileRects = layouts.indices.map { i in
            let c = i % columns, r = i / columns
            return CGRect(x: padding + CGFloat(c) * (tileWidth + spacing),
                          y: padding + CGFloat(r) * (cellHeight + spacing),
                          width: tileWidth, height: tileHeight)
        }
        let width = padding * 2 + CGFloat(columns) * tileWidth + CGFloat(columns - 1) * spacing
        let height = padding * 2 + CGFloat(rows) * cellHeight + CGFloat(rows - 1) * spacing
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        needsDisplay = true
    }

    /// Win+Z style: first digit picks the layout, second the zone.
    func typeDigit(_ digit: Int) {
        let index = digit - 1
        if let chosen = chosenLayout {
            guard index < layouts[chosen].zones.count else { return NSSound.beep() }
            onPick?(LayoutPick(layout: layouts[chosen], zoneIndex: index))
        } else {
            guard index < layouts.count else { return NSSound.beep() }
            chosenLayout = index
        }
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
        let captionFont = NSFont.systemFont(ofSize: 10, weight: .medium)

        for (i, tile) in tileRects.enumerated() {
            let layout = layouts[i]
            let dimmed = chosenLayout != nil && chosenLayout != i

            if i == activeIndex {
                accent.withAlphaComponent(0.8).setStroke()
                let ring = NSBezierPath(roundedRect: tile.insetBy(dx: -3, dy: -3), xRadius: 6, yRadius: 6)
                ring.lineWidth = 1.5
                ring.stroke()
            }

            for (z, zone) in layout.zones.enumerated() {
                let rect = zoneRect(zone, in: tile)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                let isHot = (highlighted?.layout == layout && highlighted?.zoneIndex == z) || chosenLayout == i
                (isHot ? accent : normal).withAlphaComponent(dimmed ? 0.06 : (isHot ? 0.9 : 0.16)).setFill()
                path.fill()
                (isHot ? accent : border).setStroke()
                path.lineWidth = 1
                path.stroke()

                if chosenLayout == i {
                    let label = NSAttributedString(string: "\(z + 1)", attributes: [
                        .font: NSFont.systemFont(ofSize: min(14, rect.height * 0.6), weight: .bold),
                        .foregroundColor: NSColor.white,
                    ])
                    let size = label.size()
                    label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
                }
            }

            let prefix = showsNumbers && i < 9 ? "\(i + 1)  " : ""
            let caption = NSAttributedString(string: prefix + layout.name, attributes: [
                .font: captionFont,
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(dimmed ? 0.4 : 1),
            ])
            let captionRect = NSRect(x: tile.minX, y: tile.maxY + 3, width: tile.width, height: captionHeight)
            caption.draw(with: captionRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
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
