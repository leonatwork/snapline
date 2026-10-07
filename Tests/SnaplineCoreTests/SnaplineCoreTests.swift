import CoreGraphics
import Testing
@testable import SnaplineCore

/// Samsung Odyssey G9: 5120×1440, 25pt menu bar.
let g9Screen = CGRect(x: 0, y: 0, width: 5120, height: 1440)
let g9Visible = CGRect(x: 0, y: 25, width: 5120, height: 1415)
let macbook = CGRect(x: 0, y: 0, width: 1512, height: 982)

@Suite struct ScreenClassTests {
    @Test func classifiesCommonDisplays() {
        #expect(ScreenClass(size: CGSize(width: 5120, height: 1440)) == .superWide)
        #expect(ScreenClass(size: CGSize(width: 3440, height: 1440)) == .wide)
        #expect(ScreenClass(size: CGSize(width: 2560, height: 1440)) == .standard)
        #expect(ScreenClass(size: CGSize(width: 1512, height: 982)) == .standard)
        #expect(ScreenClass(size: CGSize(width: 1440, height: 2560)) == .portrait)
    }

    @Test func superWideColumnsAreConfigurable() {
        #expect(ScreenClass.superWide.columnCount() == 3)
        #expect(ScreenClass.superWide.columnCount(superWideColumns: 4) == 4)
        #expect(ScreenClass.superWide.columnCount(superWideColumns: 9) == 4)
        #expect(ScreenClass.standard.columnCount(superWideColumns: 4) == 2)
    }
}

@Suite struct LayoutCatalogTests {
    @Test(arguments: ScreenClass.allCases)
    func everyLayoutTilesTheScreenExactly(screenClass: ScreenClass) {
        for layout in LayoutCatalog.layouts(for: screenClass) {
            let area = layout.zones.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
            #expect(abs(area - 1) < 0.0001, "\(layout.id) covers \(area)")
            for zone in layout.zones {
                #expect(zone.x >= -0.0001 && zone.maxX <= 1.0001, "\(layout.id) \(zone)")
                #expect(zone.y >= -0.0001 && zone.maxY <= 1.0001, "\(layout.id) \(zone)")
            }
        }
    }

    @Test func layoutIdsAreUniquePerClass() {
        for screenClass in ScreenClass.allCases {
            let ids = LayoutCatalog.layouts(for: screenClass).map(\.id)
            #expect(Set(ids).count == ids.count)
        }
    }

    @Test func superWideLeadsWithThirds() {
        let first = LayoutCatalog.layouts(for: .superWide)[0]
        #expect(first.zones.count == 3)
        #expect(first.zones[1].isClose(to: Zone(1.0 / 3, 0, 1.0 / 3, 1)))
    }
}

@Suite struct FrameCalculatorTests {
    @Test func thirdsOnG9WithoutGap() {
        let frames = ScreenClass.columnZones(3).map { FrameCalculator.frame(for: $0, in: g9Visible, gap: 0) }
        #expect(frames[0] == CGRect(x: 0, y: 25, width: 1707, height: 1415))
        #expect(frames[1].minX == frames[0].maxX)
        #expect(frames[2].maxX == 5120)
    }

    @Test func gapIsEvenBetweenAndAroundWindows() {
        let gap: CGFloat = 8
        let halves = ScreenClass.columnZones(2).map { FrameCalculator.frame(for: $0, in: g9Visible, gap: gap) }
        #expect(halves[0].minX == 8)
        #expect(halves[0].minY == 33)
        #expect(halves[1].minX - halves[0].maxX == 8)
        #expect(halves[1].maxX == 5112)
        #expect(halves[1].maxY == 1432)
    }

    @Test func matchToleratesCharacterGridRounding() {
        let zones = ScreenClass.columnZones(3)
        var frame = FrameCalculator.frame(for: zones[1], in: g9Visible, gap: 8)
        frame.size.width -= 9  // terminal rounding down to its cell width
        frame.size.height -= 7
        #expect(FrameCalculator.match(frame: frame, area: g9Visible, gap: 8, candidates: zones) == zones[1])
    }

    @Test func noMatchForFreeFloatingWindow() {
        let frame = CGRect(x: 600, y: 200, width: 1200, height: 800)
        #expect(FrameCalculator.match(frame: frame, area: g9Visible, gap: 8, candidates: ScreenClass.columnZones(3)) == nil)
    }
}

@Suite struct EdgeSnapResolverTests {
    let resolver = EdgeSnapResolver()

    @Test func sideEdgesSnapToOuterThirdOnG9() {
        #expect(resolver.region(for: CGPoint(x: 0, y: 700), in: g9Screen, columns: 3) == .zone(Zone(0, 0, 1.0 / 3, 1)))
        let right = resolver.region(for: CGPoint(x: 5119, y: 700), in: g9Screen, columns: 3)
        guard case .zone(let z) = right else { Issue.record("expected zone"); return }
        #expect(z.isClose(to: Zone(2.0 / 3, 0, 1.0 / 3, 1)))
    }

    @Test func sideEdgesSnapToHalvesOnStandardScreens() {
        #expect(resolver.region(for: CGPoint(x: 0, y: 500), in: macbook, columns: 2) == .zone(Zone(0, 0, 0.5, 1)))
    }

    @Test func cornersSnapToHalfColumn() {
        #expect(resolver.region(for: CGPoint(x: 0, y: 10), in: g9Screen, columns: 3) == .zone(Zone(0, 0, 1.0 / 3, 0.5)))
        #expect(resolver.region(for: CGPoint(x: 50, y: 1439), in: g9Screen, columns: 3) == .zone(Zone(0, 0.5, 1.0 / 3, 0.5)))
    }

    @Test func topEdgeMaximizesOrOpensSnapBar() {
        #expect(resolver.region(for: CGPoint(x: 2560, y: 0), in: g9Screen, columns: 3) == .snapBar)
        #expect(resolver.region(for: CGPoint(x: 1200, y: 0), in: g9Screen, columns: 3) == .maximize)
    }

    @Test func bottomEdgePicksColumnUnderCursor() {
        guard case .zone(let z) = resolver.region(for: CGPoint(x: 2560, y: 1439), in: g9Screen, columns: 3) else {
            Issue.record("expected zone"); return
        }
        #expect(z.isClose(to: Zone(1.0 / 3, 0, 1.0 / 3, 1)))

        // Four columns on 32:9: second quarter.
        guard case .zone(let q) = resolver.region(for: CGPoint(x: 1500, y: 1439), in: g9Screen, columns: 4) else {
            Issue.record("expected zone"); return
        }
        #expect(q.isClose(to: Zone(0.25, 0, 0.25, 1)))

        // Halves screens fall back to thirds on the bottom edge.
        guard case .zone(let t) = resolver.region(for: CGPoint(x: 756, y: 981), in: macbook, columns: 2) else {
            Issue.record("expected zone"); return
        }
        #expect(t.isClose(to: Zone(1.0 / 3, 0, 1.0 / 3, 1)))
    }

    @Test func interiorIsNoTarget() {
        #expect(resolver.region(for: CGPoint(x: 2000, y: 600), in: g9Screen, columns: 3) == nil)
    }

    @Test func worksOnSecondaryScreenOffset() {
        let secondary = CGRect(x: 5120, y: -200, width: 2560, height: 1440)
        #expect(resolver.region(for: CGPoint(x: 5120, y: 500), in: secondary, columns: 2) == .zone(Zone(0, 0, 0.5, 1)))
    }
}

@Suite struct KeyboardSnapTests {
    @Test func placementDetection() {
        let thirds = ScreenClass.columnZones(3)
        let center = FrameCalculator.frame(for: thirds[1], in: g9Visible, gap: 8)
        #expect(KeyboardSnap.placement(of: center, in: g9Visible, gap: 8, columns: 3) == .column(index: 1, part: .full))

        let topRight = FrameCalculator.frame(for: VerticalPart.top.apply(to: thirds[2]), in: g9Visible, gap: 8)
        #expect(KeyboardSnap.placement(of: topRight, in: g9Visible, gap: 8, columns: 3) == .column(index: 2, part: .top))

        let max = FrameCalculator.frame(for: .full, in: g9Visible, gap: 8)
        #expect(KeyboardSnap.placement(of: max, in: g9Visible, gap: 8, columns: 3) == .maximized)
    }

    @Test func leftRightWalkThroughThirds() {
        let cols = ScreenClass.columnZones(3)
        #expect(KeyboardSnap.action(for: .left, from: nil, columns: 3) == .zone(cols[0]))
        #expect(KeyboardSnap.action(for: .right, from: nil, columns: 3) == .zone(cols[2]))
        #expect(KeyboardSnap.action(for: .right, from: .column(index: 0, part: .full), columns: 3) == .zone(cols[1]))
        #expect(KeyboardSnap.action(for: .left, from: .column(index: 1, part: .top), columns: 3)
                == .zone(VerticalPart.top.apply(to: cols[0])))
        #expect(KeyboardSnap.action(for: .left, from: .column(index: 0, part: .full), columns: 3)
                == .adjacentScreen(.left, .full))
        #expect(KeyboardSnap.action(for: .right, from: .column(index: 2, part: .bottom), columns: 3)
                == .adjacentScreen(.right, .bottom))
    }

    @Test func upDownLikeWindows() {
        let cols = ScreenClass.columnZones(2)
        #expect(KeyboardSnap.action(for: .up, from: nil, columns: 2) == .maximize)
        #expect(KeyboardSnap.action(for: .up, from: .column(index: 0, part: .full), columns: 2)
                == .zone(Zone(0, 0, 0.5, 0.5)))
        #expect(KeyboardSnap.action(for: .up, from: .column(index: 1, part: .bottom), columns: 2) == .zone(cols[1]))
        #expect(KeyboardSnap.action(for: .down, from: .maximized, columns: 2) == .restore)
        #expect(KeyboardSnap.action(for: .down, from: .column(index: 0, part: .full), columns: 2)
                == .zone(Zone(0, 0.5, 0.5, 0.5)))
        #expect(KeyboardSnap.action(for: .down, from: .column(index: 0, part: .top), columns: 2) == .zone(cols[0]))
        #expect(KeyboardSnap.action(for: .down, from: nil, columns: 2) == .minimize)
    }

    @Test func edgeColumnForScreenHop() {
        #expect(KeyboardSnap.edgeColumn(.left, part: .full, columns: 2) == Zone(0, 0, 0.5, 1))
        #expect(KeyboardSnap.edgeColumn(.right, part: .top, columns: 4) == Zone(0.75, 0, 0.25, 0.5))
    }
}
