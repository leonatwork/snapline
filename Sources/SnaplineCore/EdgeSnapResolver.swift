import CoreGraphics

/// What dropping a dragged window at the current cursor position would do.
public enum SnapRegion: Equatable, Sendable {
    case zone(Zone)
    case maximize
    /// Top-center: reveal the layouts bar (Windows 11 "snap bar").
    case snapBar
}

/// Aero-Snap style edge detection. All coordinates use a top-left origin.
public struct EdgeSnapResolver: Sendable {
    /// How close (pt) the cursor must be to an edge.
    public var edgeThreshold: CGFloat
    /// Length (pt) of the corner hot areas along each edge.
    public var cornerSize: CGFloat
    /// Fraction of the top edge (centered) that opens the snap bar.
    public var snapBarFraction: CGFloat

    public init(edgeThreshold: CGFloat = 5, cornerSize: CGFloat = 140, snapBarFraction: CGFloat = 0.3) {
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
        self.snapBarFraction = snapBarFraction
    }

    /// - Parameters:
    ///   - point: cursor position.
    ///   - screen: full frame of the screen under the cursor (including the menu bar).
    ///   - columns: column count for this screen (2 = halves, 3 = thirds …).
    ///   - screens: full AX frames, used to suppress shared edge segments.
    public func region(for point: CGPoint, in screen: CGRect, columns: Int, screens: [CGRect] = []) -> SnapRegion? {
        let t = edgeThreshold
        let atLeft = point.x <= screen.minX + t
        let atRight = point.x >= screen.maxX - 1 - t
        let atTop = point.y <= screen.minY + t
        let atBottom = point.y >= screen.maxY - 1 - t
        let inner = ScreenGeometry.innerEdges(of: screen, in: screens, at: point)
        // Suppress the entire target at seam corners too: otherwise a shared top
        // edge could still produce a column through the left/right corner rule.
        if (atLeft && inner.contains(.left)) || (atRight && inner.contains(.right))
            || (atTop && inner.contains(.up)) || (atBottom && inner.contains(.down)) { return nil }
        let nearTop = point.y <= screen.minY + cornerSize
        let nearBottom = point.y >= screen.maxY - cornerSize
        let nearLeft = point.x <= screen.minX + cornerSize
        let nearRight = point.x >= screen.maxX - cornerSize

        let colW = 1 / CGFloat(max(columns, 1))

        func column(left: Bool, top: Bool?) -> SnapRegion {
            let x = left ? 0 : 1 - colW
            switch top {
            case .some(true): return .zone(Zone(x, 0, colW, 0.5))
            case .some(false): return .zone(Zone(x, 0.5, colW, 0.5))
            case .none: return .zone(Zone(x, 0, colW, 1))
            }
        }

        if atLeft || atRight {
            let top: Bool? = nearTop ? true : (nearBottom ? false : nil)
            return column(left: atLeft, top: top)
        }

        if atTop {
            if nearLeft { return column(left: true, top: true) }
            if nearRight { return column(left: false, top: true) }
            if abs(point.x - screen.midX) <= screen.width * snapBarFraction / 2 { return .snapBar }
            return .maximize
        }

        if atBottom {
            if nearLeft { return column(left: true, top: false) }
            if nearRight { return column(left: false, top: false) }
            // Bottom edge picks the column under the cursor. With only two columns
            // (halves) that would duplicate the side edges, so use thirds instead.
            let count = columns <= 2 ? 3 : columns
            let rel = (point.x - screen.minX) / max(screen.width, 1)
            let index = min(max(Int(rel * CGFloat(count)), 0), count - 1)
            return .zone(ScreenClass.columnZones(count)[index])
        }

        return nil
    }
}
