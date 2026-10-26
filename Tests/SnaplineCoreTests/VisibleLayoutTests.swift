import Foundation
import Testing
@testable import SnaplineCore

@Suite struct VisibleLayoutTests {
    private let displayA = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    private let displayB = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"

    @Test(arguments: ScreenClass.allCases)
    func legacyJSONKeepsAssignmentsNilAndOriginalOrder(screenClass: ScreenClass) throws {
        // The layouts.json array written before display assignments existed.
        let data = Data("""
        [
            {"id":"legacy-split","name":"Old split","root":{"split":{
                "axis":"columns","ratio":0.25,"first":{"leaf":{}},"second":{"leaf":{}}
            }}},
            {"id":"legacy-full","name":"Old full","root":{"leaf":{}}}
        ]
        """.utf8)
        let custom = try JSONDecoder().decode([CustomLayout].self, from: data)
        #expect(custom.map(\.id) == ["legacy-split", "legacy-full"])
        #expect(custom.allSatisfy { $0.displayIDs == nil && $0.screenClasses == nil })
        #expect(custom[0].root == .split(axis: .columns, ratio: 0.25, first: .leaf, second: .leaf))
        let previous = LayoutCatalog.layouts(for: screenClass, custom: custom.map(\.layout))
        for displayID in [displayA, displayB] {
            #expect(LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayID, custom: custom) == previous)
        }
    }

    @Test(arguments: ScreenClass.allCases)
    func screenClassRoundTripsUsingExistingRawValue(screenClass: ScreenClass) throws {
        let data = try JSONEncoder().encode(screenClass)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(screenClass.rawValue)\"")
        #expect(try JSONDecoder().decode(ScreenClass.self, from: data) == screenClass)
    }

    @Test func customAssignmentsRoundTrip() throws {
        let custom = [
            CustomLayout(id: "both", name: "Both",
                         root: .leaf.splitting(leaf: 0, axis: .rows, at: 0.3),
                         displayIDs: [displayA, displayB], screenClasses: [.portrait, .superWide]),
            CustomLayout(id: "uuid", name: "UUID", root: .leaf, displayIDs: [displayA]),
            CustomLayout(id: "class", name: "Class", root: .leaf, screenClasses: [.wide]),
            CustomLayout(id: "empty", name: "Empty", root: .leaf, displayIDs: [], screenClasses: []),
            CustomLayout(id: "global", name: "Global", root: .leaf),
        ]
        let data = try JSONEncoder().encode(custom)
        #expect(try JSONDecoder().decode([CustomLayout].self, from: data) == custom)
    }

    @Test func filtersByDisplayUUID() {
        let custom = [CustomLayout(id: "assigned", name: "Assigned", root: .leaf, displayIDs: [displayA])]
        let matching = LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom)
        let other = LayoutCatalog.visibleLayouts(for: .standard, displayID: displayB, custom: custom)
        #expect(matching == custom.map(\.layout) + LayoutCatalog.builtIn(for: .standard))
        #expect(other == LayoutCatalog.builtIn(for: .standard))
    }

    @Test(arguments: ScreenClass.allCases)
    func filtersByScreenClass(screenClass: ScreenClass) {
        let custom = [CustomLayout(id: "portrait", name: "Portrait", root: .leaf, screenClasses: [.portrait])]
        let result = LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayB, custom: custom)
        #expect(result.filter(\.isCustom).map(\.id) == (screenClass == .portrait ? ["portrait"] : []))
        #expect(result.filter { !$0.isCustom } == LayoutCatalog.builtIn(for: screenClass))
    }

    @Test func uuidAndClassAssignmentsAreCombinedWithOr() {
        let custom = [CustomLayout(id: "either", name: "Either", root: .leaf,
                                   displayIDs: [displayA], screenClasses: [.portrait])]
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom).first?.id == "either")
        #expect(LayoutCatalog.visibleLayouts(for: .portrait, displayID: displayB, custom: custom).first?.id == "either")
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayB, custom: custom)
            == LayoutCatalog.builtIn(for: .standard))
    }

    @Test(arguments: ScreenClass.allCases)
    func missingOrEmptyAssignmentsApplyEverywhere(screenClass: ScreenClass) {
        let custom = [
            CustomLayout(id: "nil", name: "Nil", root: .leaf),
            CustomLayout(id: "empty", name: "Empty", root: .leaf, displayIDs: [], screenClasses: []),
            CustomLayout(id: "empty-uuid", name: "Empty UUID", root: .leaf, displayIDs: []),
            CustomLayout(id: "empty-class", name: "Empty class", root: .leaf, screenClasses: []),
        ]
        for displayID in [displayA, displayB] {
            #expect(LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayID, custom: custom)
                == custom.map(\.layout) + LayoutCatalog.builtIn(for: screenClass))
        }
    }

    @Test func emptyAssignmentOnOneSideDoesNotBroadenTheOther() {
        let custom = [
            CustomLayout(id: "uuid", name: "UUID", root: .leaf, displayIDs: [displayA], screenClasses: []),
            CustomLayout(id: "class", name: "Class", root: .leaf, displayIDs: [], screenClasses: [.portrait]),
        ]
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayB, custom: custom)
            == LayoutCatalog.builtIn(for: .standard))
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom)
            .filter(\.isCustom).map(\.id) == ["uuid"])
        #expect(LayoutCatalog.visibleLayouts(for: .portrait, displayID: displayB, custom: custom)
            .filter(\.isCustom).map(\.id) == ["class"])
    }

    @Test func hidingBuiltInsIsLocalToEachCall() {
        let custom = [CustomLayout(id: "own", name: "Own", root: .leaf)]
        let builtIn = LayoutCatalog.builtIn(for: .standard)
        let hidden: Set<String> = ["cols-1-1", "own", "unknown"]
        let filtered = LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom,
                                                    hiddenBuiltInIDs: hidden)
        #expect(filtered == custom.map(\.layout) + builtIn.filter { $0.id != "cols-1-1" })
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayB, custom: custom)
            == custom.map(\.layout) + builtIn)
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom)
            == custom.map(\.layout) + builtIn)
    }

    @Test func orderMixesCustomAndBuiltInsAndAppendsMissingInDefaultOrder() {
        let custom = [
            CustomLayout(id: "own-a", name: "A", root: .leaf),
            CustomLayout(id: "own-b", name: "B", root: .leaf),
        ]
        let builtIn = LayoutCatalog.builtIn(for: .standard)
        let result = LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom,
                                                  order: ["cols-1-1-1", "unknown", "own-b", "cols-1-1-1"])
        let first = builtIn.first { $0.id == "cols-1-1-1" }!
        #expect(result == [first, custom[1].layout, custom[0].layout]
            + builtIn.filter { $0.id != "cols-1-1-1" })
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom, order: [])
            == custom.map(\.layout) + builtIn)
    }

    @Test(arguments: ScreenClass.allCases)
    func newCustomLayoutsAppendWithoutChangingExistingPositions(screenClass: ScreenClass) {
        let existing = CustomLayout(id: "existing", name: "Existing", root: .leaf)
        let previous = LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayA, custom: [existing])
            .reversed().map(\.id)
        let newA = CustomLayout(id: "new-a", name: "New A", root: .leaf)
        let newB = CustomLayout(id: "new-b", name: "New B", root: .leaf)
        // Even inserting new layouts at the front of the custom input cannot shift saved positions.
        let result = LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayA,
                                                  custom: [newA, existing, newB], order: previous)
        #expect(result.map(\.id) == previous + ["new-a", "new-b"])
        #expect(Array(result.suffix(2)) == [newA.layout, newB.layout])
    }

    @Test func orderCannotRestoreHiddenOrUnassignedLayouts() {
        let custom = [CustomLayout(id: "other", name: "Other", root: .leaf, displayIDs: [displayB])]
        let builtIn = LayoutCatalog.builtIn(for: .standard)
        let result = LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom,
                                                  hiddenBuiltInIDs: ["cols-1-1"],
                                                  order: ["other", "cols-1-1", "deleted", "cols-1-1-1"])
        // In Teilausdrücke zerlegt: ein einziger #expect-Ausdruck ist dem Typprüfer zu aufwendig.
        let builtInIDs: [String] = builtIn.map(\.id)
        let remaining: [String] = builtInIDs.filter { $0 != "cols-1-1" && $0 != "cols-1-1-1" }
        let expected: [String] = ["cols-1-1-1"] + remaining
        let resultIDs: [String] = result.map(\.id)
        #expect(resultIDs == expected)
    }

    @Test(arguments: ScreenClass.allCases)
    func emptyResultFallsBackToFirstBuiltInWithoutRestoringUnassignedCustom(screenClass: ScreenClass) {
        let builtIn = LayoutCatalog.builtIn(for: screenClass)
        let custom = [CustomLayout(id: "other", name: "Other", root: .leaf, displayIDs: [displayB])]
        let hidden = Set(builtIn.map(\.id))
        #expect(LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayA, custom: custom,
                                             hiddenBuiltInIDs: hidden, order: ["other"])
            == [builtIn[0]])
        #expect(LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayA, hiddenBuiltInIDs: hidden)
            == [builtIn[0]])
        #expect(LayoutCatalog.visibleLayouts(for: screenClass, displayID: displayA) == builtIn)
    }

    @Test func visibleCustomDoesNotRestoreHiddenBuiltIns() {
        let custom = [CustomLayout(id: "own", name: "Own", root: .leaf)]
        #expect(LayoutCatalog.visibleLayouts(for: .standard, displayID: displayA, custom: custom,
                                             hiddenBuiltInIDs: Set(LayoutCatalog.builtIn(for: .standard).map(\.id)))
            == custom.map(\.layout))
    }
}
