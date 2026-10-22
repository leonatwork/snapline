/// Global app exclusions. Bundle IDs retain their spelling for display/storage,
/// but membership and edits are case-insensitive. Unknown apps remain eligible.
public struct AppExclusions {
    public let bundleIDs: [String]

    public init(bundleIDs: [String] = []) {
        var seen = Set<String>()
        self.bundleIDs = bundleIDs.filter { seen.insert($0.lowercased()).inserted }
    }

    public func contains(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains { $0.lowercased() == bundleID.lowercased() }
    }

    public func adding(bundleID: String) -> AppExclusions {
        AppExclusions(bundleIDs: bundleIDs + [bundleID])
    }

    public func removing(bundleID: String) -> AppExclusions {
        AppExclusions(bundleIDs: bundleIDs.filter { $0.lowercased() != bundleID.lowercased() })
    }
}
