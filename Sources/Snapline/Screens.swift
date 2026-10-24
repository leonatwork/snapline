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
        let screens = NSScreen.screens
        guard let index = ScreenGeometry.screen(containing: point, in: screens.map(\.axFrame)) else { return nil }
        return screens[index]
    }

    /// The screen showing most of the given AX rect.
    static func screen(for rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            a.axFrame.intersection(rect).area < b.axFrame.intersection(rect).area
        }
    }

    /// Compatibility for the existing horizontal column-walking shortcuts.
    static func neighbor(of screen: NSScreen, side: HorizontalSide) -> NSScreen? {
        neighbor(of: screen, direction: side == .left ? .left : .right)
    }

    static func neighbor(of screen: NSScreen, direction: SnapDirection) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = ScreenGeometry.neighbor(of: screen.axFrame, direction: direction,
                                                  in: screens.map(\.axFrame)) else { return nil }
        return screens[index]
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
