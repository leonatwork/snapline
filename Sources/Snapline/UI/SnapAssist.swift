import AppKit
import SnaplineCore

/// After snapping a window into a layout, offer the other open windows for each
/// remaining zone – Windows 11 "Snap Assist".
@MainActor
final class SnapAssistController {
    private var panels: [Int: AssistPanel] = [:]
    private var layout: Layout?
    private var screen: NSScreen?
    private var candidates: [WindowCandidate] = []
    private var clickMonitor: Any?

    var isActive: Bool { !panels.isEmpty }

    func show(layout: Layout, filled zoneIndex: Int, on screen: NSScreen, placed window: AXWindow) {
        dismiss()
        guard layout.zones.count > 1 else { return }

        candidates = WindowList.visibleWindows(excluding: [WindowKey(window)])
        guard !candidates.isEmpty else { return }

        self.layout = layout
        self.screen = screen

        for (i, zone) in layout.zones.enumerated() where i != zoneIndex {
            let frame = Screens.toCocoa(SnapEngine.shared.frame(for: zone, on: screen))
            let panel = AssistPanel(frame: frame)
            panel.onCancel = { [weak self] in self?.dismiss() }
            panel.onPick = { [weak self] candidate in self?.fill(zoneIndex: i, with: candidate) }
            panel.show(candidates)
            panels[i] = panel
        }
        panels.values.first?.makeKey()
        loadThumbnails()

        // Clicking anywhere outside our panels ends Snap Assist, like on Windows.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    /// Live previews (Tappi's approach): cards are already on screen with icons,
    /// thumbnails fade in as they arrive.
    private func loadThumbnails() {
        let provider = ThumbnailProvider.shared
        provider.refreshPermission()
        guard Settings.livePreviews else { return }
        guard provider.isGranted else { return provider.requestAccessIfNeeded() }
        let ids = candidates.map(\.windowID)
        provider.prepare { [weak self] in
            for id in ids {
                provider.request(id, size: CGSize(width: 320, height: 200)) { image in
                    self?.panels.values.forEach { $0.setThumbnail(image, for: id) }
                }
            }
        }
    }

    private func fill(zoneIndex: Int, with candidate: WindowCandidate) {
        guard let layout, let screen else { return }
        SnapEngine.shared.snap(candidate.window, to: layout.zones[zoneIndex], on: screen)
        candidate.window.focus()

        panels.removeValue(forKey: zoneIndex)?.orderOut(nil)
        candidates.removeAll { $0.id == candidate.id }

        if panels.isEmpty || candidates.isEmpty {
            dismiss()
        } else {
            for panel in panels.values {
                panel.show(candidates)
                for c in candidates {
                    if let image = ThumbnailProvider.shared.cached(for: c.windowID) { panel.setThumbnail(image, for: c.windowID) }
                }
                // Stay above the window we just focused.
                panel.orderFrontRegardless()
            }
            panels.values.first?.makeKey()
        }
    }

    func dismiss() {
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        candidates.removeAll()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        layout = nil
        screen = nil
    }
}

@MainActor
private final class AssistPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onPick: ((WindowCandidate) -> Void)?

    private let grid = CardGridView()
    private let scroll = NSScrollView()

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        let title = NSTextField(labelWithString: "Fenster für diese Zone wählen")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = grid
        scroll.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(title)
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -16),
        ])
        contentView = background
        grid.onPick = { [weak self] in self?.onPick?($0) }
    }

    func show(_ candidates: [WindowCandidate]) {
        contentView?.layoutSubtreeIfNeeded()
        grid.setCandidates(candidates, width: scroll.contentSize.width)
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                animator().alphaValue = 1
            }
        }
    }

    func setThumbnail(_ image: NSImage, for id: CGWindowID) {
        grid.setThumbnail(image, for: id)
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Flow layout of window cards.
@MainActor
private final class CardGridView: NSView {
    var onPick: ((WindowCandidate) -> Void)?

    private let minCardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 176
    private let spacing: CGFloat = 12
    private var cards: [CGWindowID: CandidateCard] = [:]

    override var isFlipped: Bool { true }

    func setCandidates(_ candidates: [WindowCandidate], width: CGFloat) {
        subviews.forEach { $0.removeFromSuperview() }
        cards.removeAll()
        let columns = max(1, Int((width + spacing) / (minCardWidth + spacing)))
        let cardWidth = ((width - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down)

        for (i, candidate) in candidates.enumerated() {
            let c = i % columns, r = i / columns
            let card = CandidateCard(candidate: candidate)
            card.frame = NSRect(x: CGFloat(c) * (cardWidth + spacing), y: CGFloat(r) * (cardHeight + spacing),
                                width: cardWidth, height: cardHeight)
            card.onClick = { [weak self] in self?.onPick?(candidate) }
            addSubview(card)
            cards[candidate.windowID] = card
        }
        let rows = Int((Double(candidates.count) / Double(columns)).rounded(.up))
        frame = NSRect(x: 0, y: 0, width: width, height: max(CGFloat(rows) * (cardHeight + spacing) - spacing, 0))
    }

    func setThumbnail(_ image: NSImage, for id: CGWindowID) {
        cards[id]?.setThumbnail(image)
    }
}

@MainActor
private final class CandidateCard: NSView {
    var onClick: (() -> Void)?
    private var hovering = false { didSet { updateAppearance() } }
    private let preview = NSImageView()
    private let bigIcon: NSImageView

    init(candidate: WindowCandidate) {
        bigIcon = NSImageView(image: candidate.icon)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2

        // Preview area: the app icon until a live thumbnail arrives.
        let well = NSView()
        well.wantsLayer = true
        well.layer?.cornerRadius = 6
        well.layer?.masksToBounds = true
        well.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        bigIcon.imageScaling = .scaleProportionallyUpOrDown
        preview.imageScaling = .scaleProportionallyDown
        preview.alphaValue = 0

        let icon = NSImageView(image: candidate.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = NSTextField(labelWithString: candidate.title)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = "\(candidate.title) – \(candidate.appName)"
        let app = NSTextField(labelWithString: candidate.appName)
        app.font = .systemFont(ofSize: 10)
        app.textColor = .secondaryLabelColor
        app.lineBreakMode = .byTruncatingTail

        for v in [well, bigIcon, preview, icon, title, app] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(well)
        well.addSubview(bigIcon)
        well.addSubview(preview)
        for v in [icon, title, app] { addSubview(v) }

        NSLayoutConstraint.activate([
            well.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            well.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            well.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            well.bottomAnchor.constraint(equalTo: icon.topAnchor, constant: -8),
            bigIcon.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            bigIcon.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            bigIcon.widthAnchor.constraint(equalToConstant: 56),
            bigIcon.heightAnchor.constraint(equalToConstant: 56),
            preview.topAnchor.constraint(equalTo: well.topAnchor),
            preview.bottomAnchor.constraint(equalTo: well.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: well.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: well.trailingAnchor),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            title.topAnchor.constraint(equalTo: icon.topAnchor, constant: -2),
            app.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            app.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            app.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 0),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setThumbnail(_ image: NSImage) {
        preview.image = image
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            preview.animator().alphaValue = 1
            bigIcon.animator().alphaValue = 0
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = hovering
                ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                : NSColor.labelColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = hovering ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func mouseDown(with event: NSEvent) {}
}
