import CoreGraphics

public enum FrameCalculator {
    /// Converts a normalized zone into an absolute frame inside `area` (top-left origin).
    /// Outer edges get the full `gap`, edges shared with a neighbour get half, so two
    /// adjacent windows are separated by exactly `gap`.
    public static func frame(for zone: Zone, in area: CGRect, gap: CGFloat) -> CGRect {
        let eps: CGFloat = 0.001
        let left = zone.x < eps ? gap : gap / 2
        let top = zone.y < eps ? gap : gap / 2
        let right = zone.maxX > 1 - eps ? gap : gap / 2
        let bottom = zone.maxY > 1 - eps ? gap : gap / 2

        let minX = (area.minX + zone.x * area.width + left).rounded()
        let minY = (area.minY + zone.y * area.height + top).rounded()
        let maxX = (area.minX + zone.maxX * area.width - right).rounded()
        let maxY = (area.minY + zone.maxY * area.height - bottom).rounded()
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    /// Finds the zone among `candidates` whose computed frame matches `frame`.
    /// Apps such as terminals round their size to a character grid, so we allow a
    /// tolerance per edge.
    public static func match(frame: CGRect, area: CGRect, gap: CGFloat, candidates: [Zone]) -> Zone? {
        let tolerance = max(24, area.width * 0.01)
        var best: (zone: Zone, score: CGFloat)?
        for zone in candidates {
            let f = self.frame(for: zone, in: area, gap: gap)
            let deltas = [abs(f.minX - frame.minX), abs(f.minY - frame.minY),
                          abs(f.maxX - frame.maxX), abs(f.maxY - frame.maxY)]
            guard deltas.allSatisfy({ $0 <= tolerance }) else { continue }
            let score = deltas.reduce(0, +)
            if best == nil || score < best!.score { best = (zone, score) }
        }
        return best?.zone
    }
}
