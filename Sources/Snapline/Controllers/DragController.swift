import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// Watches window drags and snaps on release:
/// - plain drag: Aero Snap edges and the snap bar at the top center;
/// - drag with ⌥: the zones of the monitor's active layout (FancyZones style),
///   with Tab / 1–9 / scroll wheel to switch layouts and ⇧ to span zones.
@MainActor
final class DragController {
    private enum Target: Equatable {
        case zone(Zone, NSScreen)
        case layout(LayoutPick, NSScreen)
        case rect(CGRect)
    }

    private let flyouts: FlyoutController
    private let preview: PreviewOverlay
    private let zoneOverlay: ZoneOverlay
    private let assist: SnapAssistController
    private let resolver = EdgeSnapResolver()
    private var monitors: [Any] = []

    // Per-drag state.
    private var window: AXWindow?
    private var startFrame: CGRect = .zero
    private var startCursor: CGPoint = .zero
    private var moving = false
    private var probes = 0
    private var target: Target?
    /// Esc during a ⌥-drag: drop without snapping.
    private var cancelled = false

    // ⌥ zone mode.
    private var zoneScreen: NSScreen?
    private var zoneLayoutIndex = 0
    private var spanAnchor: Int?
    private var scrollAccumulator: Double = 0
    private var lastScrollStep: CFTimeInterval = 0

    private var store: LayoutStore { .shared }

    init(flyouts: FlyoutController, preview: PreviewOverlay, zoneOverlay: ZoneOverlay, assist: SnapAssistController) {
        self.flyouts = flyouts
        self.preview = preview
        self.zoneOverlay = zoneOverlay
        self.assist = assist
    }

    var isZoneDragging: Bool { moving && zoneScreen != nil && !cancelled }

    func start(tap: EventTap) {
        let add: (NSEvent.EventTypeMask, @escaping @MainActor (NSEvent) -> Void) -> Void = { mask, handler in
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
                MainActor.assumeIsolated { handler(event) }
            }) {
                self.monitors.append(m)
            }
        }
        add(.leftMouseDown) { [weak self] _ in self?.mouseDown() }
        add(.leftMouseDragged) { [weak self] _ in self?.mouseDragged() }
        add(.leftMouseUp) { [weak self] _ in self?.mouseUp() }

        tap.onFlagsChanged = { [weak self] _ in
            guard let self, self.moving else { return }
            self.update(cursor: Screens.cursorAX)
        }
        tap.onKeyDown = { [weak self] keyCode, flags in self?.keyDown(Int(keyCode), flags: flags) ?? false }
        tap.onScroll = { [weak self] delta in self?.scroll(delta) ?? false }
    }

    // MARK: Mouse

    private func mouseDown() {
        reset()
        guard Settings.dragSnap || Settings.optionDragZones else { return }
        let cursor = Screens.cursorAX
        guard let window = AXWindow.window(at: cursor), !window.isOwnWindow,
              window.isStandard, !window.isFullScreen,
              let frame = window.frame,
              // Only clicks in the top band can be title bar drags – skips the AX
              // polling for ordinary clicks into content.
              cursor.y - frame.minY <= 90
        else { return }

        self.window = window
        startFrame = frame
        startCursor = cursor
    }

    private func mouseDragged() {
        guard let window else { return }
        let cursor = Screens.cursorAX

        if !moving {
            guard hypot(cursor.x - startCursor.x, cursor.y - startCursor.y) > 3 else { return }
            // Find out whether this is a move (origin changes, size stays) or a resize.
            probes += 1
            guard let frame = window.frame else { reset(); return }
            if !frame.size.isRoughlyEqual(to: startFrame.size) {
                reset()  // resizing
                return
            }
            if frame.origin.isRoughlyEqual(to: startFrame.origin) {
                if probes > 10 { reset() }  // not a window drag (text selection, etc.)
                return
            }
            moving = true
            moveBegan(window: window, frame: frame, cursor: cursor)
        }

        update(cursor: cursor)
    }

    private func moveBegan(window: AXWindow, frame: CGRect, cursor: CGPoint) {
        assist.dismiss()
        if flyouts.mode != .drag { flyouts.hide() }

        // Windows behaviour: pulling a snapped window out restores its old size,
        // keeping the grab point under the cursor.
        guard Settings.restoreOnDrag,
              let rec = SnapEngine.shared.snappedRecord(for: window, currentFrame: startFrame) else { return }
        let ratio = (startCursor.x - startFrame.minX) / max(startFrame.width, 1)
        let size = rec.restore.size
        let origin = CGPoint(x: cursor.x - ratio * size.width, y: frame.minY)
        window.setFrame(CGRect(origin: origin, size: size))
        SnapEngine.shared.forget(window)
    }

    private func update(cursor: CGPoint) {
        guard !cancelled else { return }
        if Settings.optionDragZones && NSEvent.modifierFlags.contains(.option) {
            updateZones(cursor: cursor)
            return
        }
        if zoneScreen != nil { leaveZoneMode() }
        guard Settings.dragSnap else { return clearTarget() }
        updateEdges(cursor: cursor)
    }

    private func mouseUp() {
        defer { reset() }
        guard moving, !cancelled, let window, let target else { return }

        // Let the window server finish the drag before we move the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [assist] in
            MainActor.assumeIsolated {
                switch target {
                case .zone(let zone, let screen):
                    SnapEngine.shared.snap(window, to: zone, on: screen)
                case .layout(let pick, let screen):
                    SnapEngine.shared.snap(window, to: pick.zone, on: screen)
                    if Settings.snapAssist {
                        assist.show(layout: pick.layout, filled: pick.zoneIndex, on: screen, placed: window)
                    }
                case .rect(let rect):
                    SnapEngine.shared.snap(window, to: rect)
                }
            }
        }
    }

    // MARK: Edges and snap bar

    private func updateEdges(cursor: CGPoint) {
        guard let screen = Screens.screen(containingAX: cursor) else { return clearTarget() }
        let cocoaCursor = Screens.toCocoa(cursor)

        // While the snap bar is open, the cursor targets its zones.
        if flyouts.mode == .drag, flyouts.isVisible, flyouts.frame.insetBy(dx: -40, dy: -40).contains(cocoaCursor) {
            if let pick = flyouts.pickDuringDrag(atCocoa: cocoaCursor), let barScreen = flyouts.dragScreen {
                setTarget(.layout(pick, barScreen))
            } else {
                clearTarget()
            }
            return
        }

        let region = resolver.region(for: cursor, in: screen.axFrame, columns: screen.snapColumns)
        if region != .snapBar, flyouts.mode == .drag { flyouts.hide() }

        switch region {
        case .zone(let zone):
            setTarget(.zone(zone, screen))
        case .maximize:
            setTarget(.zone(.full, screen))
        case .snapBar:
            flyouts.showSnapBar(on: screen)
            clearTarget()
        case nil:
            clearTarget()
        }
    }

    private func setTarget(_ newTarget: Target) {
        target = newTarget
        switch newTarget {
        case .zone(let zone, let screen):
            preview.show(axRect: SnapEngine.shared.frame(for: zone, on: screen))
        case .layout(let pick, let screen):
            preview.show(axRect: SnapEngine.shared.frame(for: pick.zone, on: screen))
        case .rect(let rect):
            preview.show(axRect: rect)
        }
    }

    private func clearTarget() {
        target = nil
        preview.hide()
    }

    // MARK: ⌥ zones

    private func updateZones(cursor: CGPoint) {
        guard let screen = Screens.screen(containingAX: cursor) else { return }
        if zoneScreen != screen {
            if flyouts.mode == .drag { flyouts.hide() }
            preview.hide()
            zoneScreen = screen
            zoneLayoutIndex = store.activeLayoutIndex(for: screen)
            spanAnchor = nil
        }

        let layouts = store.layouts(for: screen)
        zoneLayoutIndex = min(zoneLayoutIndex, layouts.count - 1)
        let layout = layouts[zoneLayoutIndex]
        let frames = layout.zones.map { SnapEngine.shared.frame(for: $0, on: screen) }
        let hit = frames.firstIndex { $0.contains(cursor) }
            ?? frames.indices.min { frames[$0].distanceSquared(to: cursor) < frames[$1].distanceSquared(to: cursor) }
            ?? 0

        var selected: Set<Int> = [hit]
        var rect = frames[hit]
        if NSEvent.modifierFlags.contains(.shift) {
            // ⇧ spans every zone touched by the box between the first and current zone.
            let anchor = spanAnchor ?? hit
            spanAnchor = anchor
            let box = frames[anchor].union(frames[hit])
            selected = Set(frames.indices.filter { frames[$0].insetBy(dx: 4, dy: 4).intersects(box) })
            rect = selected.map { frames[$0] }.reduce(frames[hit]) { $0.union($1) }
        } else {
            spanAnchor = nil
        }

        target = .rect(rect)
        zoneOverlay.show(layout: layout, number: zoneLayoutIndex + 1, count: layouts.count, on: screen,
                         highlighted: selected, hint: "Tab / Mausrad / 1–9: Layout wechseln · ⇧: Zonen verbinden · Esc: abbrechen")
    }

    private func leaveZoneMode() {
        zoneScreen = nil
        spanAnchor = nil
        target = nil
        zoneOverlay.hide()
    }

    private func switchLayout(to index: Int) {
        guard let screen = zoneScreen else { return }
        let layouts = store.layouts(for: screen)
        guard !layouts.isEmpty else { return }
        zoneLayoutIndex = (index % layouts.count + layouts.count) % layouts.count
        spanAnchor = nil
        // Choosing a layout while dragging also makes it the monitor's active one.
        store.setActiveLayout(layouts[zoneLayoutIndex], for: screen)
        updateZones(cursor: Screens.cursorAX)
    }

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 0, kVK_ANSI_2: 1, kVK_ANSI_3: 2, kVK_ANSI_4: 3, kVK_ANSI_5: 4,
        kVK_ANSI_6: 5, kVK_ANSI_7: 6, kVK_ANSI_8: 7, kVK_ANSI_9: 8,
    ]

    /// From the event tap. Only swallows keys while a ⌥-drag is in progress.
    private func keyDown(_ keyCode: Int, flags: CGEventFlags) -> Bool {
        guard isZoneDragging else { return false }
        switch keyCode {
        case kVK_Tab:
            switchLayout(to: zoneLayoutIndex + (flags.contains(.maskShift) ? -1 : 1))
        case kVK_Escape:
            cancelled = true
            target = nil
            zoneOverlay.hide()
            preview.hide()
        default:
            guard let index = Self.digitKeys[keyCode] else { return false }
            switchLayout(to: index)
        }
        return true
    }

    private func scroll(_ delta: Double) -> Bool {
        guard isZoneDragging else { return false }
        scrollAccumulator += delta
        let now = CACurrentMediaTime()
        if abs(scrollAccumulator) >= 1, now - lastScrollStep > 0.15 {
            switchLayout(to: zoneLayoutIndex + (scrollAccumulator > 0 ? -1 : 1))
            scrollAccumulator = 0
            lastScrollStep = now
        }
        return true
    }

    private func reset() {
        window = nil
        moving = false
        probes = 0
        target = nil
        cancelled = false
        scrollAccumulator = 0
        preview.hide()
        if zoneScreen != nil { leaveZoneMode() }
        if flyouts.mode == .drag { flyouts.hide() }
    }
}

private extension CGSize {
    func isRoughlyEqual(to other: CGSize) -> Bool {
        abs(width - other.width) <= 1 && abs(height - other.height) <= 1
    }
}

private extension CGPoint {
    func isRoughlyEqual(to other: CGPoint) -> Bool {
        abs(x - other.x) <= 1 && abs(y - other.y) <= 1
    }
}

private extension CGRect {
    func distanceSquared(to p: CGPoint) -> CGFloat {
        let dx = max(minX - p.x, 0, p.x - maxX)
        let dy = max(minY - p.y, 0, p.y - maxY)
        return dx * dx + dy * dy
    }
}
