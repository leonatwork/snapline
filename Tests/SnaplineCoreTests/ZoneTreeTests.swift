import CoreGraphics
import Foundation
import Testing
@testable import SnaplineCore

@Suite struct ZoneTreeTests {
    @Test func splitIntoThirdsAndResize() {
        var tree = ZoneNode.leaf.splitting(leaf: 0, axis: .columns, at: 1.0 / 3)
        tree = tree.splitting(leaf: 1, axis: .columns, at: 0.5)
        let zones = tree.zones()
        #expect(zones.count == 3)
        #expect(zones[1].isClose(to: Zone(1.0 / 3, 0, 1.0 / 3, 1)))

        // Drag the first divider to 20 %.
        tree = tree.settingRatio(0.2, at: [])
        #expect(tree.zones()[0].isClose(to: Zone(0, 0, 0.2, 1)))
        #expect(tree.zones()[1].isClose(to: Zone(0.2, 0, 0.4, 1)))
    }

    @Test func dividersReportPositions() {
        let tree = ZoneNode.leaf.splitting(leaf: 0, axis: .columns, at: 0.25)
            .splitting(leaf: 1, axis: .rows, at: 0.5)
        let dividers = tree.dividers()
        #expect(dividers.count == 2)
        #expect(dividers[0].axis == .columns && abs(dividers[0].position - 0.25) < 0.0001)
        #expect(dividers[1].path == [1] && dividers[1].axis == .rows && abs(dividers[1].position - 0.5) < 0.0001)
    }

    @Test func removingGivesSpaceToSibling() {
        let tree = ZoneNode.leaf.splitting(leaf: 0, axis: .columns, at: 0.5)
            .splitting(leaf: 1, axis: .rows, at: 0.5)
        let removed = tree.removing(leaf: 2)
        #expect(removed.zones() == [Zone(0, 0, 0.5, 1), Zone(0.5, 0, 0.5, 1)])
        #expect(ZoneNode.leaf.removing(leaf: 0) == .leaf)
    }

    @Test func ratiosAreClamped() {
        let tree = ZoneNode.leaf.splitting(leaf: 0, axis: .rows, at: 0.999)
        guard case let .split(_, ratio, _, _) = tree else { Issue.record("expected split"); return }
        #expect(ratio == 1 - ZoneNode.minRatio)
    }

    @Test(arguments: ScreenClass.allCases)
    func everyBuiltInLayoutConvertsToTree(screenClass: ScreenClass) {
        for layout in LayoutCatalog.builtIn(for: screenClass) {
            guard let tree = ZoneNode.from(zones: layout.zones) else {
                Issue.record("\(layout.id) is not convertible"); continue
            }
            let rebuilt = tree.zones()
            #expect(rebuilt.count == layout.zones.count, "\(layout.id)")
            for zone in layout.zones {
                #expect(rebuilt.contains { $0.isClose(to: zone) }, "\(layout.id) lost \(zone)")
            }
        }
    }

    @Test func roundTripsThroughJSON() throws {
        let layout = CustomLayout(id: "x", name: "20/60/20",
                                  root: ZoneNode.leaf.splitting(leaf: 0, axis: .columns, at: 0.2)
                                      .splitting(leaf: 1, axis: .columns, at: 0.75))
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(CustomLayout.self, from: data) == layout)
        #expect(layout.layout.isCustom)
    }
}

@Suite struct WorkspaceTests {
    struct W { let bundle: String; let title: String }

    @Test func titleMatchesWinThenOrder() {
        let saved = [
            WorkspaceWindow(bundleID: "com.google.Chrome", appName: "Chrome", title: "Docs", displayID: nil, displayIndex: 0, zone: .full),
            WorkspaceWindow(bundleID: "com.google.Chrome", appName: "Chrome", title: "Mail", displayID: nil, displayIndex: 0, zone: .full),
            WorkspaceWindow(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: "", displayID: nil, displayIndex: 0, zone: .full),
            WorkspaceWindow(bundleID: "com.apple.Terminal", appName: "Terminal", title: "zsh", displayID: nil, displayIndex: 0, zone: .full),
        ]
        let open = [
            W(bundle: "com.google.Chrome", title: "Mail"),
            W(bundle: "com.tinyspeck.slackmacgap", title: "Slack | general"),
            W(bundle: "com.google.Chrome", title: "Something else"),
        ]
        let pairs = WorkspaceMatcher.assign(saved: saved, open: open, bundleID: \.bundle, title: \.title)
        #expect(pairs.map(\.saved) == [0, 1, 2])
        #expect(pairs.map(\.open) == [2, 0, 1])
    }

    @Test func zoneFrameRoundTrip() {
        let area = CGRect(x: 0, y: 25, width: 5120, height: 1415)
        let frame = CGRect(x: 1707, y: 25, width: 1706, height: 1415)
        #expect(Zone(frame: frame, in: area).rect(in: area) == frame)
    }
}
