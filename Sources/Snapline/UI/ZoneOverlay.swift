import AppKit
import SnaplineCore

/// Full-screen overlay showing the zones of a layout – used while dragging with ⌥
/// (FancyZones style) and as a short confirmation when switching layouts.
@MainActor
final class ZoneOverlay {
    private let window: NSWindow
    private let view = ZoneOverlayView()
    private var fadeWork: DispatchWorkItem?

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.contentView = view
    }

    var isVisible: Bool { window.isVisible }

    /// - Parameters:
    ///   - number: 1-based position of the layout in the screen's list.
    ///   - hint: secondary line under the layout name.
    func show(layout: Layout, number: Int, count: Int, on screen: NSScreen, highlighted: Set<Int>, hint: String?) {
        fadeWork?.cancel()
        fadeWork = nil
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        view.configure(layout: layout, number: number, count: count, screen: screen,
                       highlighted: highlighted, hint: hint)
        if !window.isVisible {
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            window.animator().alphaValue = 1
        }
    }

    /// Briefly shows a layout, then fades out – confirmation for ⌃⌥1…9.
    func flash(layout: Layout, number: Int, count: Int, on screen: NSScreen) {
        show(layout: layout, number: number, count: count, on: screen, highlighted: [],
             hint: L10n.tr("zones.activeLayoutHint"))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func hide() {
        fadeWork?.cancel()
        fadeWork = nil
        guard window.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.fadeWork == nil, self.window.alphaValue == 0 else { return }
                self.window.orderOut(nil)
            }
        })
    }
}

@MainActor
private final class ZoneOverlayView: NSView {
    private var layout: Layout?
    private var number = 1
    private var count = 1
    private var zoneRects: [CGRect] = []
    private var highlighted: Set<Int> = []
    private var hint: String?
    private var headerTop: CGFloat = 0

    override var isFlipped: Bool { true }

    func configure(layout: Layout, number: Int, count: Int, screen: NSScreen, highlighted: Set<Int>, hint: String?) {
        self.layout = layout
        self.number = number
        self.count = count
        self.highlighted = highlighted
        self.hint = hint
        // Zone frames are in AX coordinates; make them relative to this screen.
        let origin = screen.axFrame.origin
        zoneRects = layout.zones.map {
            SnapEngine.shared.frame(for: $0, on: screen).offsetBy(dx: -origin.x, dy: -origin.y)
        }
        headerTop = screen.axVisibleFrame.minY - origin.y + 16
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout else { return }
        let accent = NSColor.controlAccentColor

        for (i, rect) in zoneRects.enumerated() {
            let inset = rect.insetBy(dx: 6, dy: 6)
            let path = NSBezierPath(roundedRect: inset, xRadius: 14, yRadius: 14)
            let hot = highlighted.contains(i)
            accent.withAlphaComponent(hot ? 0.38 : 0.12).setFill()
            path.fill()
            accent.withAlphaComponent(hot ? 1 : 0.55).setStroke()
            path.lineWidth = hot ? 3 : 1.5
            path.stroke()

            let label = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: min(96, inset.height / 4), weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(hot ? 0.95 : 0.6),
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2))
        }

        drawHeader(title: "\(layout.displayName)   \(number)/\(count)")
    }

    private func drawHeader(title: String) {
        let titleString = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let hintString = hint.map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white.withAlphaComponent(0.75),
            ])
        }
        let titleSize = titleString.size()
        let hintSize = hintString?.size() ?? .zero
        let width = max(titleSize.width, hintSize.width) + 36
        let height = titleSize.height + (hintString == nil ? 0 : hintSize.height + 4) + 20
        let pill = NSRect(x: bounds.midX - width / 2, y: headerTop, width: width, height: height)

        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        titleString.draw(at: NSPoint(x: pill.midX - titleSize.width / 2, y: pill.minY + 10))
        hintString?.draw(at: NSPoint(x: pill.midX - hintSize.width / 2, y: pill.minY + 14 + titleSize.height))
    }
}
