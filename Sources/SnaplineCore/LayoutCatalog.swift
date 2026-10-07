import CoreGraphics

/// The built-in layouts, tailored per screen shape – like Windows 11, which shows
/// more options on wider displays. User layouts are listed in front of these.
public enum LayoutCatalog {
    public static func builtIn(for screenClass: ScreenClass) -> [Layout] {
        switch screenClass {
        case .portrait:
            return [
                .rows("rows-2", "Zeilen ½", [1, 1]),
                .rows("rows-3", "Zeilen ⅓", [1, 1, 1]),
                .rows("rows-2-1", "Zeilen ⅔ + ⅓", [2, 1]),
                .grid("grid-2x2", "Raster 2×2", columns: 2, rows: 2),
            ]
        case .standard:
            return [
                .columns("cols-1-1", "Hälften", [1, 1]),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
                .columns("cols-1-1-1", "Drittel", [1, 1, 1]),
                halfAndStack,
                .grid("grid-2x2", "Raster 2×2", columns: 2, rows: 2),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
            ]
        case .wide:
            return [
                .columns("cols-1-1", "Hälften", [1, 1]),
                .columns("cols-1-1-1", "Drittel", [1, 1, 1]),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
                halfAndStack,
                .grid("grid-2x2", "Raster 2×2", columns: 2, rows: 2),
            ]
        case .superWide:
            return [
                .columns("cols-1-1-1", "Drittel", [1, 1, 1]),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
                .columns("cols-1-1-1-1", "Viertel", [1, 1, 1, 1]),
                .columns("cols-1-1", "Hälften", [1, 1]),
                thirdsWithStack,
                stacksAroundCenter,
                .grid("grid-3x2", "Raster 3×2", columns: 3, rows: 2),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
            ]
        }
    }

    /// Everything offered on a screen: the user's own layouts first, then built-ins.
    /// This order is also what ⌃⌥1…9 selects from.
    public static func layouts(for screenClass: ScreenClass, custom: [Layout] = []) -> [Layout] {
        custom + builtIn(for: screenClass)
    }

    /// Left half, right half split into two rows.
    static let halfAndStack = Layout(id: "half-stack", name: "½ + Stapel", zones: [
        Zone(0, 0, 0.5, 1),
        Zone(0.5, 0, 0.5, 0.5),
        Zone(0.5, 0.5, 0.5, 0.5),
    ])

    /// Two full-height thirds, the right third split into two rows.
    static let thirdsWithStack = Layout(id: "thirds-stack", name: "Drittel + Stapel", zones: [
        Zone(0, 0, 1.0 / 3, 1),
        Zone(1.0 / 3, 0, 1.0 / 3, 1),
        Zone(2.0 / 3, 0, 1.0 / 3, 0.5),
        Zone(2.0 / 3, 0.5, 1.0 / 3, 0.5),
    ])

    /// Quarter-width stacks on both sides of a centered half – great for 32:9.
    static let stacksAroundCenter = Layout(id: "stacks-center", name: "Stapel · ½ · Stapel", zones: [
        Zone(0, 0, 0.25, 0.5),
        Zone(0, 0.5, 0.25, 0.5),
        Zone(0.25, 0, 0.5, 1),
        Zone(0.75, 0, 0.25, 0.5),
        Zone(0.75, 0.5, 0.25, 0.5),
    ])

    /// Number of flyout tile columns, so the flyout stays compact on any display.
    public static func flyoutColumns(for screenClass: ScreenClass) -> Int {
        switch screenClass {
        case .portrait, .superWide: return 4
        case .standard, .wide: return 3
        }
    }
}
