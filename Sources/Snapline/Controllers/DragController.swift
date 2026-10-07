import AppKit
import SnaplineCore

/// Aero Snap and the snap bar: watches window drags and snaps on release.
@MainActor
final class DragController {
    private enum Target: Equatable {
        case zone(Zone, NSScreen)
        case layout(LayoutPick, NSScreen)
    }

    private let flyouts: FlyoutController
    private let preview: PreviewOverlay
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

    init(flyouts: FlyoutController, preview: PreviewOverlay, assist: SnapAssistController) {
        self.flyouts = flyouts
        self.preview = preview
        self.assist = assist
    }

    func start() {
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
    }

    private func mouseDown() {
        reset()
        guard Settings.dragSnap else { return }
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
        guard let screen = Screens.screen(containingAX: cursor) else { return clearTarget() }
        let cocoaCursor = Screens.toCocoa(cursor)

        // While the snap bar is open, the cursor targets its zones.
        if flyouts.mode == .drag, flyouts.isVisible, flyouts.frame.insetBy(dx: -40, dy: -40).contains(cocoaCursor) {
            if let pick = flyouts.pickDuringDrag(atCocoa: cocoaCursor), let barScreen = flyouts.dragScreen {
                setTarget(.layout(pick, barScreen))
            } else {
                target = nil
                preview.hide()
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
            target = nil
            preview.hide()
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

    private func mouseUp() {
        defer { reset() }
        guard moving, let window, let target else { return }

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
                }
            }
        }
    }

    private func reset() {
        window = nil
        moving = false
        probes = 0
        target = nil
        preview.hide()
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
