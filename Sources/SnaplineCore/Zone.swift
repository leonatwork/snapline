import CoreGraphics

/// A rectangle in normalized screen space (0…1), origin top-left.
public struct Zone: Hashable, Sendable, Codable, CustomStringConvertible {
    public var x: CGFloat
    public var y: CGFloat
    public var width: CGFloat
    public var height: CGFloat

    public init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = Zone(0, 0, 1, 1)

    public var maxX: CGFloat { x + width }
    public var maxY: CGFloat { y + height }

    public var description: String {
        func f(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
        return "Zone(\(f(x)), \(f(y)), \(f(width)), \(f(height)))"
    }

    /// Approximate equality, tolerant of floating point error from fractions like 1/3.
    public func isClose(to other: Zone, tolerance: CGFloat = 0.001) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

/// A named arrangement of zones, as shown in the Snap Layouts flyout.
public struct Layout: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let zones: [Zone]
    /// User-made layouts can be edited; built-in ones only duplicated.
    public let isCustom: Bool

    public init(id: String, name: String, zones: [Zone], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.zones = zones
        self.isCustom = isCustom
    }

    /// Side-by-side columns with the given relative widths (normalized automatically).
    public static func columns(_ id: String, _ name: String, _ widths: [CGFloat]) -> Layout {
        let total = widths.reduce(0, +)
        var x: CGFloat = 0
        var zones: [Zone] = []
        for w in widths {
            let nw = w / total
            zones.append(Zone(x, 0, nw, 1))
            x += nw
        }
        return Layout(id: id, name: name, zones: zones)
    }

    /// Stacked rows with the given relative heights (normalized automatically).
    public static func rows(_ id: String, _ name: String, _ heights: [CGFloat]) -> Layout {
        let total = heights.reduce(0, +)
        var y: CGFloat = 0
        var zones: [Zone] = []
        for h in heights {
            let nh = h / total
            zones.append(Zone(0, y, 1, nh))
            y += nh
        }
        return Layout(id: id, name: name, zones: zones)
    }

    /// A uniform grid, zones ordered row by row.
    public static func grid(_ id: String, _ name: String, columns: Int, rows: Int) -> Layout {
        var zones: [Zone] = []
        for r in 0..<rows {
            for c in 0..<columns {
                zones.append(Zone(CGFloat(c) / CGFloat(columns), CGFloat(r) / CGFloat(rows),
                                  1 / CGFloat(columns), 1 / CGFloat(rows)))
            }
        }
        return Layout(id: id, name: name, zones: zones)
    }
}
