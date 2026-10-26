import CoreGraphics

public enum SplitAxis: String, Codable, Sendable {
    /// Side by side – the divider is a vertical line.
    case columns
    /// Stacked – the divider is a horizontal line.
    case rows
}

/// A layout as a tree of splits. Every tree tiles its area without gaps or overlaps,
/// which makes it a safe model for the layout editor: split a zone, drag a divider,
/// remove a zone – the result is always a valid layout.
public indirect enum ZoneNode: Codable, Equatable, Sendable {
    case leaf
    /// `ratio` is the share of the first child along `axis`.
    case split(axis: SplitAxis, ratio: CGFloat, first: ZoneNode, second: ZoneNode)

    public static let minRatio: CGFloat = 0.05

    /// A draggable divider: the split node at `path` and its line position.
    public struct Divider: Equatable, Sendable {
        public let path: [Int]
        public let axis: SplitAxis
        /// Normalized x (for `.columns`) or y (for `.rows`) of the line.
        public let position: CGFloat
        /// The area the split node covers.
        public let area: Zone
    }

    // MARK: Reading

    /// Leaf zones in depth-first order (first child before second).
    public func zones(in area: Zone = .full) -> [Zone] {
        switch self {
        case .leaf:
            return [area]
        case let .split(axis, ratio, first, second):
            let (a, b) = Self.divide(area, axis: axis, ratio: ratio)
            return first.zones(in: a) + second.zones(in: b)
        }
    }

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case let .split(_, _, first, second): return first.leafCount + second.leafCount
        }
    }

    public func dividers(in area: Zone = .full, path: [Int] = []) -> [Divider] {
        guard case let .split(axis, ratio, first, second) = self else { return [] }
        let (a, b) = Self.divide(area, axis: axis, ratio: ratio)
        let position = axis == .columns ? a.maxX : a.maxY
        return [Divider(path: path, axis: axis, position: position, area: area)]
            + first.dividers(in: a, path: path + [0])
            + second.dividers(in: b, path: path + [1])
    }

    static func divide(_ area: Zone, axis: SplitAxis, ratio: CGFloat) -> (Zone, Zone) {
        switch axis {
        case .columns:
            let w = area.width * ratio
            return (Zone(area.x, area.y, w, area.height), Zone(area.x + w, area.y, area.width - w, area.height))
        case .rows:
            let h = area.height * ratio
            return (Zone(area.x, area.y, area.width, h), Zone(area.x, area.y + h, area.width, area.height - h))
        }
    }

    // MARK: Editing

    /// Splits leaf number `index` at `fraction` (0…1 within that leaf) along `axis`.
    public func splitting(leaf index: Int, axis: SplitAxis, at fraction: CGFloat = 0.5) -> ZoneNode {
        var counter = 0
        return mapLeaf(index, counter: &counter) { _ in
            .split(axis: axis, ratio: Self.clamp(fraction), first: .leaf, second: .leaf)
        }
    }

    /// Removes leaf number `index`; its sibling takes over the space.
    public func removing(leaf index: Int) -> ZoneNode {
        guard case let .split(axis, ratio, first, second) = self else { return self }
        let firstCount = first.leafCount
        if index < firstCount {
            if case .leaf = first { return second }
            return .split(axis: axis, ratio: ratio, first: first.removing(leaf: index), second: second)
        } else {
            if case .leaf = second { return first }
            return .split(axis: axis, ratio: ratio, first: first,
                          second: second.removing(leaf: index - firstCount))
        }
    }

    /// Moves the divider of the split node at `path`.
    public func settingRatio(_ ratio: CGFloat, at path: [Int]) -> ZoneNode {
        guard case let .split(axis, current, first, second) = self else { return self }
        guard let head = path.first else {
            return .split(axis: axis, ratio: Self.clamp(ratio), first: first, second: second)
        }
        let rest = Array(path.dropFirst())
        return head == 0
            ? .split(axis: axis, ratio: current, first: first.settingRatio(ratio, at: rest), second: second)
            : .split(axis: axis, ratio: current, first: first, second: second.settingRatio(ratio, at: rest))
    }

    private func mapLeaf(_ index: Int, counter: inout Int, _ transform: (ZoneNode) -> ZoneNode) -> ZoneNode {
        switch self {
        case .leaf:
            defer { counter += 1 }
            return counter == index ? transform(self) : self
        case let .split(axis, ratio, first, second):
            let f = first.mapLeaf(index, counter: &counter, transform)
            let s = second.mapLeaf(index, counter: &counter, transform)
            return .split(axis: axis, ratio: ratio, first: f, second: s)
        }
    }

    static func clamp(_ ratio: CGFloat) -> CGFloat {
        min(max(ratio, minRatio), 1 - minRatio)
    }

    // MARK: Conversion

    /// Rebuilds a tree from a flat zone list (used to turn a built-in layout into an
    /// editable copy). Returns nil if the zones cannot be separated by straight cuts.
    public static func from(zones: [Zone], in area: Zone = .full) -> ZoneNode? {
        let eps: CGFloat = 0.0001
        guard !zones.isEmpty else { return nil }
        if zones.count == 1 { return zones[0].isClose(to: area, tolerance: 0.001) ? .leaf : nil }

        for axis in [SplitAxis.columns, .rows] {
            let cuts = Set(zones.map { axis == .columns ? $0.maxX : $0.maxY })
                .filter { axis == .columns ? ($0 > area.x + eps && $0 < area.maxX - eps)
                                           : ($0 > area.y + eps && $0 < area.maxY - eps) }
                .sorted()
            for cut in cuts {
                let before = zones.filter { (axis == .columns ? $0.maxX : $0.maxY) <= cut + eps }
                let after = zones.filter { (axis == .columns ? $0.x : $0.y) >= cut - eps }
                guard before.count + after.count == zones.count else { continue }
                let ratio = axis == .columns ? (cut - area.x) / area.width : (cut - area.y) / area.height
                let (a, b) = divide(area, axis: axis, ratio: ratio)
                if let first = from(zones: before, in: a), let second = from(zones: after, in: b) {
                    return .split(axis: axis, ratio: ratio, first: first, second: second)
                }
            }
        }
        return nil
    }
}

/// A layout made in the editor.
public struct CustomLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var root: ZoneNode
    /// Stable display UUID strings (the app's displayKey), not numeric display IDs.
    public var displayIDs: [String]?
    /// Combined with displayIDs using OR. Both nil/empty means every display.
    public var screenClasses: [ScreenClass]?

    public init(id: String, name: String, root: ZoneNode,
                displayIDs: [String]? = nil, screenClasses: [ScreenClass]? = nil) {
        self.id = id
        self.name = name
        self.root = root
        self.displayIDs = displayIDs
        self.screenClasses = screenClasses
    }

    public var layout: Layout {
        Layout(id: id, name: name, zones: root.zones(), isCustom: true)
    }
}
