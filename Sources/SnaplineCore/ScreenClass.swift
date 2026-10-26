import CoreGraphics

/// Display shape, derived from the aspect ratio. Drives which layouts and how many
/// snap columns a screen gets.
public enum ScreenClass: String, Codable, Sendable, CaseIterable {
    /// Taller than wide.
    case portrait
    /// 16:9, 16:10, 3:2 …
    case standard
    /// 21:9 ultrawide.
    case wide
    /// 32:9 super ultrawide (Samsung G9, Dell U49 …).
    case superWide

    public init(size: CGSize) {
        let ratio = size.width / max(size.height, 1)
        switch ratio {
        case ..<1.0: self = .portrait
        case ..<2.1: self = .standard
        case ..<3.0: self = .wide
        default: self = .superWide
        }
    }

    /// Number of columns used for edge snapping and keyboard cycling.
    /// `superWideColumns` is user-configurable (2, 3 or 4).
    public func columnCount(superWideColumns: Int = 3) -> Int {
        switch self {
        case .portrait, .standard, .wide: return 2
        case .superWide: return min(max(superWideColumns, 2), 4)
        }
    }

    /// Column zones (full height) for the given count.
    public static func columnZones(_ count: Int) -> [Zone] {
        let n = CGFloat(max(count, 1))
        return (0..<max(count, 1)).map { Zone(CGFloat($0) / n, 0, 1 / n, 1) }
    }
}
