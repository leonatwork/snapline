import CoreGraphics
import Testing
@testable import SnaplineCore

@Suite struct ScreenGeometryTests {
    let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)

    @Test func sharedEdgesBelongToRightOrLowerScreenRegardlessOfListOrder() {
        for screens in [[left, primary, above], [above, primary, left]] {
            #expect(ScreenGeometry.screen(containing: CGPoint(x: 0, y: 500), in: screens).map { screens[$0] } == primary)
            #expect(ScreenGeometry.screen(containing: CGPoint(x: 500, y: 0), in: screens).map { screens[$0] } == primary)
            #expect(ScreenGeometry.screen(containing: CGPoint(x: -1920, y: 500), in: screens).map { screens[$0] } == left)
            #expect(ScreenGeometry.screen(containing: CGPoint(x: 500, y: -1080), in: screens).map { screens[$0] } == above)
        }
        let fartherLeft = left.offsetBy(dx: -1920, dy: 0)
        let fartherAbove = above.offsetBy(dx: 0, dy: -1080)
        #expect(ScreenGeometry.screen(containing: CGPoint(x: -1920, y: 500), in: [left, fartherLeft]) == 0)
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 500, y: -1080), in: [above, fartherAbove]) == 0)
        // Shared-edge endpoints on the outer perimeter keep the same ownership.
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 0, y: 1080), in: [left, primary]) == 1)
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 1920, y: 0), in: [above, primary]) == 1)
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 1920, y: 1080), in: [primary]) == 0)
        #expect(ScreenGeometry.screen(containing: CGPoint(x: 1921, y: 500), in: [primary]) == nil)
        #expect(ScreenGeometry.screen(containing: .zero, in: []) == nil)
    }

    @Test func neighborsInAllFourDirectionsAndNoWrap() {
        let right = primary.offsetBy(dx: 1920, dy: 0)
        let below = primary.offsetBy(dx: 0, dy: 1080)
        let screens = [primary, left, right, above, below]
        #expect(ScreenGeometry.neighbor(of: primary, direction: .left, in: screens) == 1)
        #expect(ScreenGeometry.neighbor(of: primary, direction: .right, in: screens) == 2)
        #expect(ScreenGeometry.neighbor(of: primary, direction: .up, in: screens) == 3)
        #expect(ScreenGeometry.neighbor(of: primary, direction: .down, in: screens) == 4)
        for direction in SnapDirection.allCases {
            #expect(ScreenGeometry.neighbor(of: primary, direction: direction, in: [primary]) == nil)
        }
        #expect(ScreenGeometry.innerEdges(of: primary, in: screens) == Set(SnapDirection.allCases))
        #expect(ScreenGeometry.innerEdges(of: primary, in: [primary]).isEmpty)
    }

    @Test func adjacencyRequiresOnePointOfOverlapWithOnePointTolerance() {
        let touching = CGRect(x: 1921, y: 1079, width: 1000, height: 1000)
        #expect(ScreenGeometry.neighbor(of: primary, direction: .right, in: [primary, touching]) == 1)
        for other in [touching.offsetBy(dx: 0.1, dy: 0), touching.offsetBy(dx: 0, dy: 0.1),
                      CGRect(x: 1920, y: 1080, width: 1000, height: 1000)] {
            #expect(ScreenGeometry.neighbor(of: primary, direction: .right, in: [primary, other]) == nil)
            #expect(ScreenGeometry.innerEdges(of: primary, in: [primary, other]).isEmpty)
        }
    }

    @Test func neighborTieBreakIsGeometricNotListOrder() {
        let upper = CGRect(x: 1920, y: -460, width: 1000, height: 1000)
        let lower = CGRect(x: 1920, y: 540, width: 1000, height: 1000)
        for screens in [[primary, upper, lower], [lower, primary, upper]] {
            let index = ScreenGeometry.neighbor(of: primary, direction: .right, in: screens)
            #expect(index.map { screens[$0] } == upper)
        }
    }

    @Test func superWideAndOffsetPortraitOnlySharePartOfEdge() {
        let wide = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        let portrait = CGRect(x: 5120, y: -800, width: 1440, height: 2560)
        #expect(ScreenGeometry.neighbor(of: wide, direction: .right, in: [wide, portrait]) == 1)
        #expect(ScreenGeometry.innerEdges(of: portrait, in: [wide, portrait], at: CGPoint(x: 5120, y: 700)) == [.left])
        #expect(ScreenGeometry.innerEdges(of: portrait, in: [wide, portrait], at: CGPoint(x: 5120, y: -400)).isEmpty)
    }

    @Test func transferUsesRelativeVisiblePositionAndSizeInEveryDirection() {
        let source = CGRect(x: 0, y: 25, width: 2000, height: 1000)
        let frame = CGRect(x: 200, y: 225, width: 1000, height: 500)
        for target in [CGRect(x: -1000, y: 50, width: 1000, height: 800),
                       CGRect(x: 2000, y: 50, width: 1000, height: 800),
                       CGRect(x: 0, y: -800, width: 1000, height: 800),
                       CGRect(x: 0, y: 1100, width: 1000, height: 800)] {
            #expect(ScreenGeometry.transfer(frame, from: source, to: target)
                    == CGRect(x: target.minX + 100, y: target.minY + 160, width: 500, height: 400))
        }
    }

    @Test func transferKeepsRecordedZoneAndTargetGapRatherThanScalingGap() {
        let target = CGRect(x: -1440, y: -800, width: 1440, height: 2500)
        for zone in [Zone.full, Zone(1.0 / 3, 0.5, 1.0 / 3, 0.5), Zone(0.2, 0.1, 0.6, 0.8)] {
            let frame = FrameCalculator.frame(for: zone, in: g9Visible, gap: 8)
            #expect(ScreenGeometry.transfer(frame, from: g9Visible, to: target, zone: zone, gap: 8)
                    == FrameCalculator.frame(for: zone, in: target, gap: 8))
        }
    }

    @Test func clampMovesAndShrinksFramesButAnchorsUnavoidableMinimumSize() {
        let area = CGRect(x: -1000, y: -800, width: 1000, height: 800)
        #expect(ScreenGeometry.clamp(CGRect(x: -1200, y: -900, width: 600, height: 500), to: area)
                == CGRect(x: -1000, y: -800, width: 600, height: 500))
        #expect(ScreenGeometry.clamp(CGRect(x: -100, y: -100, width: 600, height: 500), to: area)
                == CGRect(x: -600, y: -500, width: 600, height: 500))
        // AX read-back: minimum size exceeds the requested zone but fits the screen.
        #expect(ScreenGeometry.clamp(CGRect(x: -100, y: -100, width: 600, height: 500), to: area, resize: false)
                == CGRect(x: -600, y: -500, width: 600, height: 500))
        let oversized = CGRect(x: 100, y: 100, width: 1200, height: 900)
        #expect(ScreenGeometry.clamp(oversized, to: area) == area)
        #expect(ScreenGeometry.clamp(oversized, to: area, resize: false)
                == CGRect(origin: area.origin, size: oversized.size))
        let tooWide = CGRect(x: 100, y: 100, width: 1200, height: 200)
        #expect(ScreenGeometry.clamp(tooWide, to: area, resize: false)
                == CGRect(origin: area.origin, size: tooWide.size))
        #expect(ScreenGeometry.clamp(area.insetBy(dx: 100, dy: 100), to: area) == area.insetBy(dx: 100, dy: 100))
    }
}

@Suite struct MultiMonitorEdgeSnapTests {
    let resolver = EdgeSnapResolver()
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func sharedSideHasNoPreviewOnEitherSideIncludingCorners() {
        let left = screen.offsetBy(dx: -1920, dy: 0)
        for y in [0, 50, 500, 1079] as [CGFloat] {
            for x in [-5, -1, 0, 5] as [CGFloat] {
                let point = CGPoint(x: x, y: y)
                let current = x < 0 ? left : screen
                #expect(resolver.region(for: point, in: current, columns: 2, screens: [screen, left]) == nil)
            }
        }
        #expect(resolver.region(for: CGPoint(x: -1920, y: 500), in: left, columns: 2, screens: [screen, left])
                == .zone(Zone(0, 0, 0.5, 1)))
    }

    @Test func stackedSeamCannotMaximizeOpenBarOrSnapColumn() {
        let above = screen.offsetBy(dx: 0, dy: -1080)
        for x in [0, 50, 400, 960, 1870, 1919] as [CGFloat] {
            for y in [-5, -1, 0, 5] as [CGFloat] {
                #expect(resolver.region(for: CGPoint(x: x, y: y), in: y < 0 ? above : screen,
                                        columns: 2, screens: [above, screen]) == nil)
            }
        }
        #expect(resolver.region(for: CGPoint(x: 960, y: -1080), in: above, columns: 2,
                                screens: [above, screen]) == .snapBar)
    }

    @Test func exposedPortionOfOffsetEdgeStillSnaps() {
        let right = CGRect(x: 1920, y: 400, width: 1080, height: 1920)
        #expect(resolver.region(for: CGPoint(x: 1919, y: 700), in: screen, columns: 2, screens: [screen, right]) == nil)
        #expect(resolver.region(for: CGPoint(x: 1919, y: 200), in: screen, columns: 2, screens: [screen, right])
                == .zone(Zone(0.5, 0, 0.5, 1)))
    }

    @Test func singleScreenRetainsAllExistingEdgeTargets() {
        for point in [CGPoint(x: 0, y: 500), CGPoint(x: 1919, y: 500), CGPoint(x: 960, y: 0),
                      CGPoint(x: 400, y: 0), CGPoint(x: 960, y: 1079), CGPoint(x: 50, y: 1079),
                      CGPoint(x: 960, y: 500)] {
            #expect(resolver.region(for: point, in: screen, columns: 2, screens: [screen])
                    == resolver.region(for: point, in: screen, columns: 2))
        }
    }
}
