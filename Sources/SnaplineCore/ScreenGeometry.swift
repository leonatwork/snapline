import CoreGraphics

/// Display geometry in AX coordinates (top-left origin, y increasing downwards).
/// Screen indices always refer to the supplied list; no AppKit or display state.
public enum ScreenGeometry {
    /// Exact shared edges belong to the right/lower screen: min edges are inclusive,
    /// max edges exclusive. Exposed max edges are included as a fallback, without
    /// expanding frames; shared min edges still win at perimeter endpoints.
    /// Overlapping/mirrored frames use geometric order (top, left,
    /// height, width), then list index only for identical frames. Negative coordinates
    /// follow exactly the same rule.
    public static func screen(containing point: CGPoint, in screens: [CGRect]) -> Int? {
        func contains(_ frame: CGRect, includeMax: Bool) -> Bool {
            valid(frame) && point.x >= frame.minX && point.y >= frame.minY
                && (includeMax ? point.x <= frame.maxX : point.x < frame.maxX)
                && (includeMax ? point.y <= frame.maxY : point.y < frame.maxY)
        }
        let interior = screens.indices.filter { contains(screens[$0], includeMax: false) }
        let candidates = interior.isEmpty
            ? screens.indices.filter { contains(screens[$0], includeMax: true) } : interior
        return candidates.min { a, b in
            if interior.isEmpty {
                let lowerA = point.y == screens[a].minY
                let lowerB = point.y == screens[b].minY
                if lowerA != lowerB { return lowerA }
                let rightA = point.x == screens[a].minX
                let rightB = point.x == screens[b].minX
                if rightA != rightB { return rightA }
            }
            return precedes(screens[a], screens[b])
        }
    }

    /// Touching edges (within 1 pt) with at least 1 pt of shared span are neighbours.
    /// Multiple neighbours: greatest shared span, then nearest perpendicular centre,
    /// then geometric order. Corner-only contacts and gaps over 1 pt do not qualify;
    /// there is no wraparound.
    public static func neighbor(of screen: CGRect, direction: SnapDirection, in screens: [CGRect]) -> Int? {
        let candidates = screens.indices.filter { sharedSpan(screen, screens[$0], direction: direction) != nil }
        return candidates.min { a, b in
            let spanA = sharedSpan(screen, screens[a], direction: direction)!
            let spanB = sharedSpan(screen, screens[b], direction: direction)!
            let overlapA = spanA.upperBound - spanA.lowerBound
            let overlapB = spanB.upperBound - spanB.lowerBound
            if overlapA != overlapB { return overlapA > overlapB }
            let horizontal = direction == .left || direction == .right
            let center = horizontal ? screen.midY : screen.midX
            let distanceA = abs((horizontal ? screens[a].midY : screens[a].midX) - center)
            let distanceB = abs((horizontal ? screens[b].midY : screens[b].midX) - center)
            if distanceA != distanceB { return distanceA < distanceB }
            return precedes(screens[a], screens[b])
        }
    }

    /// Edges with a neighbour, optionally restricted to the shared span at `point`.
    /// This preserves snapping on exposed portions of offset displays. Shared span
    /// endpoints are inclusive so a seam corner cannot trigger another edge target.
    public static func innerEdges(of screen: CGRect, in screens: [CGRect], at point: CGPoint? = nil) -> Set<SnapDirection> {
        Set(SnapDirection.allCases.filter { direction in
            screens.contains { other in
                guard let span = sharedSpan(screen, other, direction: direction) else { return false }
                guard let point else { return true }
                let coordinate = direction == .left || direction == .right ? point.y : point.x
                return span.contains(coordinate)
            }
        })
    }

    /// Relative position AND size in visible frames. Recorded snap zones are
    /// recalculated with the target gap rather than scaling the source's gap.
    public static func transfer(_ frame: CGRect, from source: CGRect, to target: CGRect,
                                zone: Zone? = nil, gap: CGFloat = 0) -> CGRect {
        guard valid(source), valid(target) else { return frame }
        if let zone { return clamp(FrameCalculator.frame(for: zone, in: target, gap: gap), to: target) }
        let result = CGRect(x: target.minX + (frame.minX - source.minX) / source.width * target.width,
                            y: target.minY + (frame.minY - source.minY) / source.height * target.height,
                            width: frame.width / source.width * target.width,
                            height: frame.height / source.height * target.height)
        return clamp(result, to: target)
    }

    /// Move inside `area`, shrinking only when needed. Use `resize: false` after
    /// reading an app's actual AX frame: if its minimum size cannot fit, keep that
    /// size and anchor the whole frame at the target's top-left corner.
    public static func clamp(_ frame: CGRect, to area: CGRect, resize: Bool = true) -> CGRect {
        guard valid(frame), valid(area) else { return frame }
        if !resize && (frame.width > area.width || frame.height > area.height) {
            return CGRect(origin: area.origin, size: frame.size)
        }
        let width = resize ? min(frame.width, area.width) : frame.width
        let height = resize ? min(frame.height, area.height) : frame.height
        return CGRect(x: min(max(frame.minX, area.minX), area.maxX - width),
                      y: min(max(frame.minY, area.minY), area.maxY - height), width: width, height: height)
    }

    private static func sharedSpan(_ screen: CGRect, _ other: CGRect, direction: SnapDirection) -> ClosedRange<CGFloat>? {
        guard valid(screen), valid(other), screen != other else { return nil }
        let distance: CGFloat
        let lower: CGFloat
        let upper: CGFloat
        switch direction {
        case .left:
            guard other.midX < screen.midX else { return nil }
            distance = abs(screen.minX - other.maxX)
            lower = max(screen.minY, other.minY)
            upper = min(screen.maxY, other.maxY)
        case .right:
            guard other.midX > screen.midX else { return nil }
            distance = abs(screen.maxX - other.minX)
            lower = max(screen.minY, other.minY)
            upper = min(screen.maxY, other.maxY)
        case .up:
            guard other.midY < screen.midY else { return nil }
            distance = abs(screen.minY - other.maxY)
            lower = max(screen.minX, other.minX)
            upper = min(screen.maxX, other.maxX)
        case .down:
            guard other.midY > screen.midY else { return nil }
            distance = abs(screen.maxY - other.minY)
            lower = max(screen.minX, other.minX)
            upper = min(screen.maxX, other.maxX)
        }
        guard distance <= 1, upper - lower >= 1 else { return nil }
        return lower...upper
    }

    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
    }

    private static func precedes(_ a: CGRect, _ b: CGRect) -> Bool {
        if a.minY != b.minY { return a.minY < b.minY }
        if a.minX != b.minX { return a.minX < b.minX }
        if a.height != b.height { return a.height < b.height }
        return a.width < b.width
    }
}
