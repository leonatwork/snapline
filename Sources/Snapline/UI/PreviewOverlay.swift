import AppKit

/// The translucent "acrylic" rectangle that shows where a dragged window will land.
@MainActor
final class PreviewOverlay {
    private let window: NSWindow
    private var targetAX: CGRect?
    /// Bumped on every show, so a pending fade-out can tell it has been superseded.
    private var generation = 0

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

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.cornerRadius = 12
        tint.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        tint.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        tint.layer?.borderWidth = 2
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)

        window.contentView = blur
    }

    func show(axRect: CGRect) {
        guard targetAX != axRect else { return }
        targetAX = axRect
        generation += 1
        let frame = Screens.toCocoa(axRect)
        if window.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
                window.animator().alphaValue = 1
            }
        } else {
            // Grow out from the cursor like Windows does.
            let cursor = NSEvent.mouseLocation
            window.setFrame(NSRect(x: cursor.x - 20, y: cursor.y - 20, width: 40, height: 40), display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
                window.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard window.isVisible, targetAX != nil else { return }
        targetAX = nil
        let hiding = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == hiding else { return }
                self.window.orderOut(nil)
            }
        })
    }
}
