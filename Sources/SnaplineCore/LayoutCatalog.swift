import CoreGraphics

/// The built-in layouts, tailored per screen shape – like Windows 11, which shows
/// more options on wider displays. User layouts lead the default order.
public enum LayoutCatalog {
    public static func builtIn(for screenClass: ScreenClass) -> [Layout] {
        switch screenClass {
        case .portrait:
            return [
                .rows("rows-2", "Rows ½", [1, 1]),
                .rows("rows-3", "Rows ⅓", [1, 1, 1]),
                .rows("rows-2-1", "Rows ⅔ + ⅓", [2, 1]),
                .grid("grid-2x2", "Grid 2×2", columns: 2, rows: 2),
            ]
        case .standard:
            return [
                .columns("cols-1-1", "Halves", [1, 1]),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
                .columns("cols-1-1-1", "Thirds", [1, 1, 1]),
                halfAndStack,
                .grid("grid-2x2", "Grid 2×2", columns: 2, rows: 2),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
            ]
        case .wide:
            return [
                .columns("cols-1-1", "Halves", [1, 1]),
                .columns("cols-1-1-1", "Thirds", [1, 1, 1]),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
                halfAndStack,
                .grid("grid-2x2", "Grid 2×2", columns: 2, rows: 2),
            ]
        case .superWide:
            return [
                .columns("cols-1-1-1", "Thirds", [1, 1, 1]),
                .columns("cols-1-2-1", "¼ · ½ · ¼", [1, 2, 1]),
                .columns("cols-1-1-1-1", "Quarters", [1, 1, 1, 1]),
                .columns("cols-1-1", "Halves", [1, 1]),
                thirdsWithStack,
                stacksAroundCenter,
                .grid("grid-3x2", "Grid 3×2", columns: 3, rows: 2),
                .columns("cols-2-1", "⅔ + ⅓", [2, 1]),
            ]
        }
    }

    /// Everything offered on a screen: the user's own layouts first, then built-ins.
    /// This order is also what ⌃⌥1…9 selects from.
    public static func layouts(for screenClass: ScreenClass, custom: [Layout] = []) -> [Layout] {
        custom + builtIn(for: screenClass)
    }

    /// Computes a display's visible layouts without reading or changing stored preferences.
    /// `displayID` is its stable UUID string (the app's displayKey).
    /// Assignments match by UUID OR screen class; both nil/empty means all displays.
    /// Only built-ins can be hidden. Without an order, matching custom layouts come first.
    /// With an order, known visible IDs come first; unknown/repeated IDs are ignored and
    /// missing layouts follow in default order. Pass all previous visible IDs to keep their
    /// positions stable when adding custom layouts: new layouts then appear at the end.
    /// If nothing remains, restores the first built-in of the class, even if hidden.
    public static func visibleLayouts(for screenClass: ScreenClass, displayID: String,
                                      custom: [CustomLayout] = [],
                                      hiddenBuiltInIDs: Set<String> = [], order: [String] = []) -> [Layout] {
        let matching = custom.filter { layout in
            let unassigned = (layout.displayIDs?.isEmpty ?? true) && (layout.screenClasses?.isEmpty ?? true)
            return unassigned || (layout.displayIDs?.contains(displayID) ?? false)
                || (layout.screenClasses?.contains(screenClass) ?? false)
        }.map(\.layout)
        let templates = builtIn(for: screenClass)
        let available = matching + templates.filter { !hiddenBuiltInIDs.contains($0.id) }
        // Every screen class has built-ins. Never bring back an unassigned custom layout.
        guard !available.isEmpty else { return [templates[0]] }

        var result: [Layout] = []
        var placed: Set<String> = []
        for id in order {
            guard !placed.contains(id), let layout = available.first(where: { $0.id == id }) else { continue }
            result.append(layout)
            placed.insert(id)
        }
        return result + available.filter { !placed.contains($0.id) }
    }

    /// Left half, right half split into two rows.
    static let halfAndStack = Layout(id: "half-stack", name: "½ + stack", zones: [
        Zone(0, 0, 0.5, 1),
        Zone(0.5, 0, 0.5, 0.5),
        Zone(0.5, 0.5, 0.5, 0.5),
    ])

    /// Two full-height thirds, the right third split into two rows.
    static let thirdsWithStack = Layout(id: "thirds-stack", name: "Thirds + stack", zones: [
        Zone(0, 0, 1.0 / 3, 1),
        Zone(1.0 / 3, 0, 1.0 / 3, 1),
        Zone(2.0 / 3, 0, 1.0 / 3, 0.5),
        Zone(2.0 / 3, 0.5, 1.0 / 3, 0.5),
    ])

    /// Quarter-width stacks on both sides of a centered half – great for 32:9.
    static let stacksAroundCenter = Layout(id: "stacks-center", name: "Stack · ½ · stack", zones: [
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
