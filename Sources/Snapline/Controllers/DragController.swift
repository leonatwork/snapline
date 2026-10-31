import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// Watches window drags and snaps on release:
/// - plain drag: Aero Snap edges and the snap bar at the top center;
/// - drag with the zone key (⌘ by default): the zones of the monitor's active
///   layout (FancyZones style), with scroll wheel / 1–9 / Tab to switch layouts and
///   ⇧ to span zones.
@MainActor
final class DragController {
    private enum Target: Equatable {
        case zone(Zone, NSScreen)
        case layout(LayoutPick, NSScreen)
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
    /// Window server ID of the dragged window – its bounds update immediately,
    /// unlike AX positions, which apps like Electron report with a delay.
    private var windowID: CGWindowID?
    /// When the cursor first moved past the drag threshold.
    private var dragStartedAt: CFTimeInterval?
    private var target: Target?
    /// Esc during a zone drag: drop without snapping.
    private var cancelled = false

    // Zone mode.
    private var zoneScreen: NSScreen?
    private var zoneLayoutIndex = 0
    private var spanAnchor: Int?
    private var scrollAccumulator: Double = 0
    /// Modifier keys as of the latest event. Read from the events themselves:
    /// `NSEvent.modifierFlags` can still report the old state while the event tap
    /// is handling a key press, so pressing the zone key mid-drag would be missed.
    private var flags: NSEvent.ModifierFlags = []
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
        add(.leftMouseDown) { [weak self] event in
            self?.flags = event.modifierFlags
            self?.mouseDown()
        }
        add(.leftMouseDragged) { [weak self] event in
            self?.flags = event.modifierFlags
            self?.mouseDragged()
        }
        add(.leftMouseUp) { [weak self] _ in self?.mouseUp() }

        tap.onFlagsChanged = { [weak self] cgFlags in
            guard let self else { return }
            // CGEventFlags and NSEvent.ModifierFlags share the same bit layout.
            self.flags = NSEvent.ModifierFlags(rawValue: UInt(cgFlags.rawValue))
            debugLog("flags changed: zone key held \(self.zoneKeyHeld), moving \(self.moving)")
            guard self.moving else { return }
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
        guard let window = AXWindow.window(at: cursor) else {
            return debugLog("mouseDown: no window under cursor")
        }
        guard !window.isOwnWindow, !window.isAppExcluded, window.isStandard, !window.isFullScreen, let frame = window.frame else {
            return debugLog("mouseDown: ignored window (subrole \(window.subrole ?? "nil"), own \(window.isOwnWindow), fullscreen \(window.isFullScreen), frame \(String(describing: window.frame)))")
        }
        // Only clicks in the top band can be title bar drags – skips the AX
        // polling for ordinary clicks into content.
        guard cursor.y - frame.minY <= 90 else { return }
        self.window = window
        windowID = Self.windowNumber(at: cursor, pid: window.pid)
        startFrame = windowID.flatMap(Self.bounds(of:)) ?? frame
        startCursor = cursor
        debugLog("mouseDown: candidate \(startFrame) id \(windowID.map(String.init) ?? "–")")
    }

    /// Frontmost normal window of `pid` under the cursor, from the window server.
    private static func windowNumber(at point: CGPoint, pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict), bounds.contains(point) else { continue }
            // The topmost window under the cursor must be the one we clicked.
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == pid else { return nil }
            return entry[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    private static func bounds(of id: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let dict = info.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    private func currentFrame(of window: AXWindow) -> CGRect? {
        if let windowID, let bounds = Self.bounds(of: windowID) { return bounds }
        return window.frame
    }

    private func mouseDragged() {
        guard let window else { return }
        guard !window.isAppExcluded else { reset(); return }
        let cursor = Screens.cursorAX

        if !moving {
            guard hypot(cursor.x - startCursor.x, cursor.y - startCursor.y) > 3 else { return }
            // Find out whether this is a move (origin changes, size stays) or a resize.
            let now = CACurrentMediaTime()
            if dragStartedAt == nil { dragStartedAt = now }
            guard let frame = currentFrame(of: window) else { reset(); return }
            if !frame.size.isRoughlyEqual(to: startFrame.size) {
                debugLog("drag: resize, ignoring")
                reset()
                return
            }
            if frame.origin.isRoughlyEqual(to: startFrame.origin) {
                // Give up only after real time and distance – a 1000 Hz mouse sends
                // dozens of events before a window has visibly moved.
                let travelled = hypot(cursor.x - startCursor.x, cursor.y - startCursor.y)
                if now - dragStartedAt! > 0.8 && travelled > 40 {
                    debugLog("drag: window did not move (\(Int(travelled)) pt in \(Int((now - dragStartedAt!) * 1000)) ms), ignoring")
                    reset()
                }
                return
            }
            debugLog("drag: window move began (zone key \(Settings.zoneModifier.symbol) held: \(zoneKeyHeld))")
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

    private var zoneKeyHeld: Bool { flags.contains(Settings.zoneModifier.flag) }

    private func update(cursor: CGPoint) {
        guard let window, !window.isAppExcluded else { reset(); return }
        guard !cancelled else { return }
        if Settings.optionDragZones && zoneKeyHeld {
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
                guard !window.isAppExcluded else { return }
                switch target {
                case .zone(let zone, let screen):
                    SnapEngine.shared.snap(window, to: zone, on: screen)
                case .layout(let pick, let screen):
                    SnapEngine.shared.snap(window, to: pick.zone, on: screen)
                    if Settings.snapAssist {
                        assist.show(layout: pick.layout, filled: pick.zoneIndex, on: screen, placed: window)
                    }
                }
            }
        }
    }

    // MARK: Edges and snap bar

    private func updateEdges(cursor: CGPoint) {
        guard let screen = Screens.screen(containingAX: cursor) else {
            if flyouts.mode == .drag { flyouts.hide() }
            return clearTarget()
        }
        let cocoaCursor = Screens.toCocoa(cursor)
        let region = resolver.region(for: cursor, in: screen.axFrame, columns: screen.snapColumns,
                                     screens: NSScreen.screens.map(\.axFrame))
        // A bar opened on an outer edge must not keep targeting zones after the
        // cursor crosses onto a shared edge or another display.
        let inner = ScreenGeometry.innerEdges(of: screen.axFrame, in: NSScreen.screens.map(\.axFrame), at: cursor)
        let t = resolver.edgeThreshold
        let atInner = (inner.contains(.left) && cursor.x <= screen.axFrame.minX + t)
            || (inner.contains(.right) && cursor.x >= screen.axFrame.maxX - 1 - t)
            || (inner.contains(.up) && cursor.y <= screen.axFrame.minY + t)
            || (inner.contains(.down) && cursor.y >= screen.axFrame.maxY - 1 - t)
        if flyouts.mode == .drag, atInner || flyouts.dragScreen != screen { flyouts.hide() }

        // While the snap bar is open, the cursor targets its zones.
        if flyouts.mode == .drag, flyouts.isVisible, flyouts.frame.insetBy(dx: -40, dy: -40).contains(cocoaCursor) {
            if let pick = flyouts.pickDuringDrag(atCocoa: cocoaCursor), let barScreen = flyouts.dragScreen {
                setTarget(.layout(pick, barScreen))
            } else {
                clearTarget()
            }
            return
        }

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
            debugLog("zones: showing \(store.layouts(for: screen)[zoneLayoutIndex].name) on \(screen.localizedName)")
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
        let modifier = Settings.zoneModifier
        if flags.contains(modifier.spanFlag) {
            // ⇧ (or ⌥ when ⇧ is the zone key) spans every zone touched by the box between the first and current zone.
            let anchor = spanAnchor ?? hit
            spanAnchor = anchor
            let box = frames[anchor].union(frames[hit])
            selected = Set(frames.indices.filter { frames[$0].insetBy(dx: 4, dy: 4).intersects(box) })
            rect = selected.map { frames[$0] }.reduce(frames[hit]) { $0.union($1) }
        } else {
            spanAnchor = nil
        }

        // Remember the normalized zone (including spans), not just its pixel
        // frame, so a monitor move preserves the zone and recalculates the gap.
        let zone = selected.reduce(layout.zones[hit]) { bounds, index in
            let next = layout.zones[index]
            let x = min(bounds.x, next.x)
            let y = min(bounds.y, next.y)
            return Zone(x, y, max(bounds.maxX, next.maxX) - x, max(bounds.maxY, next.maxY) - y)
        }
        target = .zone(zone, screen)
        zoneOverlay.show(layout: layout, number: zoneLayoutIndex + 1, count: layouts.count, on: screen,
                         highlighted: selected,
                         hint: L10n.tr("zones.hint", modifier.spanSymbol))
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

    func appExclusionsDidChange() {
        if window?.isAppExcluded == true { reset() }
    }

    private func reset() {
        window = nil
        moving = false
        windowID = nil
        dragStartedAt = nil
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
