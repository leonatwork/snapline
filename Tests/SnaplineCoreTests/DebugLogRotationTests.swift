import Testing
@testable import SnaplineCore

@Suite struct DebugLogRotationTests {
    @Test func belowLimitDoesNotRotate() {
        #expect(!DebugLogRotation.shouldRotate(fileSize: 0))
        #expect(!DebugLogRotation.shouldRotate(fileSize: 999_999))
    }

    @Test func exactlyOneMBDoesNotRotate() {
        #expect(!DebugLogRotation.shouldRotate(fileSize: 1_000_000))
    }

    @Test func aboveOneMBRotates() {
        #expect(DebugLogRotation.shouldRotate(fileSize: 1_000_001))
        #expect(DebugLogRotation.shouldRotate(fileSize: UInt64.max))
    }
}
