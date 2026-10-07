import CoreGraphics

public enum SnapDirection: Sendable {
    case left, right, up, down
}

public enum HorizontalSide: Sendable {
    case left, right
}

/// Which part of a column a window occupies.
public enum VerticalPart: Sendable, CaseIterable {
    case full, top, bottom

    public func apply(to column: Zone) -> Zone {
        switch self {
        case .full: return column
        case .top: return Zone(column.x, 0, column.width, 0.5)
        case .bottom: return Zone(column.x, 0.5, column.width, 0.5)
        }
    }
}

/// Where a window currently sits, as far as keyboard snapping is concerned.
public enum Placement: Equatable, Sendable {
    case maximized
    case column(index: Int, part: VerticalPart)
}

public enum KeyboardSnapAction: Equatable, Sendable {
    case zone(Zone)
    case maximize
    case restore
    case minimize
    /// Continue onto the neighbouring display: snap to its column closest to us.
    case adjacentScreen(HorizontalSide, VerticalPart)
}

/// Win + Arrow behaviour, generalised to N columns so 32:9 screens cycle through thirds.
public enum KeyboardSnap {
    public static func placement(of frame: CGRect, in area: CGRect, gap: CGFloat, columns: Int) -> Placement? {
        var candidates: [(Zone, Placement)] = [(.full, .maximized)]
        for (i, col) in ScreenClass.columnZones(columns).enumerated() {
            for part in VerticalPart.allCases {
                candidates.append((part.apply(to: col), .column(index: i, part: part)))
            }
        }
        guard let zone = FrameCalculator.match(frame: frame, area: area, gap: gap, candidates: candidates.map(\.0))
        else { return nil }
        return candidates.first { $0.0 == zone }?.1
    }

    public static func action(for direction: SnapDirection, from placement: Placement?, columns: Int) -> KeyboardSnapAction {
        let cols = ScreenClass.columnZones(columns)
        let last = cols.count - 1

        switch (direction, placement) {
        case (.left, .column(let i, let part)):
            return i > 0 ? .zone(part.apply(to: cols[i - 1])) : .adjacentScreen(.left, part)
        case (.right, .column(let i, let part)):
            return i < last ? .zone(part.apply(to: cols[i + 1])) : .adjacentScreen(.right, part)
        case (.left, _):
            return .zone(cols[0])
        case (.right, _):
            return .zone(cols[last])

        case (.up, .column(let i, .full)):
            return .zone(VerticalPart.top.apply(to: cols[i]))
        case (.up, .column(let i, .bottom)):
            return .zone(cols[i])
        case (.up, _):
            return .maximize

        case (.down, .maximized):
            return .restore
        case (.down, .column(let i, .full)):
            return .zone(VerticalPart.bottom.apply(to: cols[i]))
        case (.down, .column(let i, .top)):
            return .zone(cols[i])
        case (.down, _):
            return .minimize
        }
    }

    /// Column on the given edge of a screen, used when moving across displays.
    public static func edgeColumn(_ side: HorizontalSide, part: VerticalPart, columns: Int) -> Zone {
        let cols = ScreenClass.columnZones(columns)
        return part.apply(to: side == .left ? cols[0] : cols[cols.count - 1])
    }
}
