import AppKit
import SnaplineCore

/// Conversion between Cocoa coordinates (origin bottom-left of the primary display,
/// y up) and AX/CoreGraphics coordinates (origin top-left of the primary display, y down).
enum Screens {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func toAX(_ p: NSPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    static func toCocoa(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: primaryHeight - p.y) }

    static func toAX(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func toCocoa(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// Current cursor position in AX coordinates.
    static var cursorAX: CGPoint { toAX(NSEvent.mouseLocation) }

    static func screen(containingAX point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.axFrame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// The screen showing most of the given AX rect.
    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.axFrame.intersection(rect).area < b.axFrame.intersection(rect).area
        }
    }

    /// Nearest screen to the left/right whose vertical span overlaps ours.
    static func neighbor(of screen: NSScreen, side: HorizontalSide) -> NSScreen? {
        let f = screen.axFrame
        let others = NSScreen.screens.filter { $0 != screen }
        let candidates = others.filter { o in
            let of = o.axFrame
            let overlaps = of.maxY > f.minY && of.minY < f.maxY
            return overlaps && (side == .left ? of.midX < f.midX : of.midX > f.midX)
        }
        return candidates.min { a, b in abs(a.axFrame.midX - f.midX) < abs(b.axFrame.midX - f.midX) }
    }
}

extension NSScreen {
    var axFrame: CGRect { Screens.toAX(frame) }
    var axVisibleFrame: CGRect { Screens.toAX(visibleFrame) }
    var screenClass: ScreenClass { ScreenClass(size: frame.size) }
    var snapColumns: Int { screenClass.columnCount(superWideColumns: Settings.superWideColumns) }
}

extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
