import Testing
@testable import SnaplineCore

@Suite struct AppExclusionsTests {
    @Test func emptyListAllowsEveryApp() {
        let exclusions = AppExclusions()
        #expect(exclusions.bundleIDs.isEmpty)
        #expect(!exclusions.contains(bundleID: "com.apple.Preview"))
        #expect(!exclusions.contains(bundleID: nil))
    }

    @Test func matchesOnlyWholeBundleIDs() {
        let exclusions = AppExclusions(bundleIDs: ["com.apple.Preview"])
        #expect(exclusions.contains(bundleID: "com.apple.Preview"))
        #expect(!exclusions.contains(bundleID: "com.apple.Terminal"))
        #expect(!exclusions.contains(bundleID: "com.apple.Preview.Helper"))
        #expect(!exclusions.contains(bundleID: "com.apple"))
    }

    @Test func comparisonIgnoresCaseAndAllowsUnknownApps() {
        let exclusions = AppExclusions(bundleIDs: ["com.apple.Preview"])
        #expect(exclusions.contains(bundleID: "COM.APPLE.PREVIEW"))
        #expect(!exclusions.contains(bundleID: nil))
    }

    @Test func addingDoesNotDuplicateOrChangeOriginal() {
        let original = AppExclusions(bundleIDs: ["com.apple.Preview"])
        let added = original.adding(bundleID: "com.apple.Terminal")
            .adding(bundleID: "COM.APPLE.PREVIEW")
            .adding(bundleID: "com.apple.Terminal")
        #expect(original.bundleIDs == ["com.apple.Preview"])
        #expect(added.bundleIDs == ["com.apple.Preview", "com.apple.Terminal"])
    }

    @Test func firstExclusionCanBeAddedAndRemoved() {
        let added = AppExclusions().adding(bundleID: "com.apple.Preview")
        #expect(added.contains(bundleID: "com.apple.Preview"))
        #expect(added.bundleIDs == ["com.apple.Preview"])
        #expect(added.removing(bundleID: "com.apple.Preview").bundleIDs.isEmpty)
        #expect(AppExclusions().removing(bundleID: "com.apple.Preview").bundleIDs.isEmpty)
    }

    @Test func storedListDeduplicatesAndRoundTrips() {
        let exclusions = AppExclusions(bundleIDs: ["com.apple.Preview", "COM.APPLE.PREVIEW", "com.apple.Terminal"])
        #expect(exclusions.bundleIDs == ["com.apple.Preview", "com.apple.Terminal"])
        let reloaded = AppExclusions(bundleIDs: exclusions.bundleIDs)
        #expect(reloaded.contains(bundleID: "COM.APPLE.PREVIEW"))
        #expect(reloaded.bundleIDs == exclusions.bundleIDs)
    }

    @Test func removingIgnoresCaseAndPreservesOtherApps() {
        let original = AppExclusions(bundleIDs: ["com.apple.Preview", "com.apple.Terminal"])
        let removed = original.removing(bundleID: "COM.APPLE.PREVIEW")
        #expect(!removed.contains(bundleID: "com.apple.Preview"))
        #expect(removed.bundleIDs == ["com.apple.Terminal"])
        #expect(original.contains(bundleID: "com.apple.Preview"))
        #expect(removed.removing(bundleID: "unknown.app").bundleIDs == removed.bundleIDs)
        #expect(removed.removing(bundleID: "com.apple.Terminal").bundleIDs.isEmpty)
    }
}
