import CoreGraphics

/// One window of a saved arrangement.
public struct WorkspaceWindow: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    /// Stable display identifier (CGDisplay UUID), if known.
    public var displayID: String?
    /// Position of the display among all screens when saved – fallback if the UUID is gone.
    public var displayIndex: Int
    /// Frame relative to the display's visible area.
    public var zone: Zone

    public init(bundleID: String, appName: String, title: String, displayID: String?, displayIndex: Int, zone: Zone) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.displayID = displayID
        self.displayIndex = displayIndex
        self.zone = zone
    }
}

/// A saved arrangement of app windows, restorable with one shortcut.
public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var windows: [WorkspaceWindow]

    public init(id: String, name: String, windows: [WorkspaceWindow]) {
        self.id = id
        self.name = name
        self.windows = windows
    }
}

public enum WorkspaceMatcher {
    /// Pairs saved windows with currently open ones of the same app: windows whose
    /// title still matches win first, the rest are paired in order.
    /// Returns (savedIndex, openIndex) pairs.
    public static func assign<W>(saved: [WorkspaceWindow], open: [W],
                                 bundleID: (W) -> String, title: (W) -> String) -> [(saved: Int, open: Int)] {
        var usedOpen = Set<Int>()
        var result: [Int: Int] = [:]

        for (i, s) in saved.enumerated() where !s.title.isEmpty {
            if let j = open.indices.first(where: {
                !usedOpen.contains($0) && bundleID(open[$0]) == s.bundleID && title(open[$0]) == s.title
            }) {
                usedOpen.insert(j)
                result[i] = j
            }
        }
        for (i, s) in saved.enumerated() where result[i] == nil {
            if let j = open.indices.first(where: { !usedOpen.contains($0) && bundleID(open[$0]) == s.bundleID }) {
                usedOpen.insert(j)
                result[i] = j
            }
        }
        return result.sorted { $0.key < $1.key }.map { (saved: $0.key, open: $0.value) }
    }
}

extension Zone {
    /// `frame` expressed relative to `area`.
    public init(frame: CGRect, in area: CGRect) {
        self.init((frame.minX - area.minX) / max(area.width, 1), (frame.minY - area.minY) / max(area.height, 1),
                  frame.width / max(area.width, 1), frame.height / max(area.height, 1))
    }

    /// Absolute frame inside `area`, without gaps.
    public func rect(in area: CGRect) -> CGRect {
        CGRect(x: (area.minX + x * area.width).rounded(), y: (area.minY + y * area.height).rounded(),
               width: (width * area.width).rounded(), height: (height * area.height).rounded())
    }
}
