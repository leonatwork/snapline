import AppKit

/// A window offered in Snap Assist.
struct WindowCandidate: Identifiable {
    let id = UUID()
    let window: AXWindow
    let windowID: CGWindowID
    let bundleID: String?
    let frame: CGRect
    let title: String
    let appName: String
    let icon: NSImage
}

enum WindowList {
    /// Visible standard windows of other apps, front to back.
    ///
    /// `CGWindowList` provides the on-screen order and bounds (no Screen Recording
    /// permission needed for those); AX provides the controllable element and title.
    static func visibleWindows(excluding excluded: Set<WindowKey> = []) -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var axCache: [pid_t: [AXWindow]] = [:]
        var used = Set<WindowKey>()
        var result: [WindowCandidate] = []
        let ownPid = getpid()

        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 100, bounds.height >= 60,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular
            else { continue }

            let axWindows = axCache[pid] ?? AXWindow.windows(of: pid)
            axCache[pid] = axWindows

            guard let match = axWindows.first(where: { w in
                guard let f = w.frame, !used.contains(WindowKey(w)) else { return false }
                return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2
                    && abs(f.width - bounds.width) < 2 && abs(f.height - bounds.height) < 2
            }), match.isStandard else { continue }

            let key = WindowKey(match)
            guard !excluded.contains(key) else { continue }
            used.insert(key)

            let appName = app.localizedName ?? ""
            let title = match.title.isEmpty ? appName : match.title
            result.append(WindowCandidate(window: match, windowID: windowID, bundleID: app.bundleIdentifier,
                                          frame: bounds, title: title, appName: appName,
                                          icon: app.icon ?? NSImage(named: NSImage.applicationIconName)!))
        }
        return result
    }
}
