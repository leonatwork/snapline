import AppKit
import SnaplineCore

/// Saves the current window arrangement and brings it back on demand,
/// launching apps that are not running.
@MainActor
final class WorkspaceController {
    private var store: LayoutStore { .shared }
    private var restoreTimer: Timer?

    /// Snapshot of all visible app windows on all displays.
    func capture(name: String, id: String = UUID().uuidString) -> Workspace {
        let screens = NSScreen.screens
        let windows: [WorkspaceWindow] = WindowList.visibleWindows().compactMap { c in
            guard let bundleID = c.bundleID, let screen = Screens.screen(for: c.frame) else { return nil }
            return WorkspaceWindow(bundleID: bundleID, appName: c.appName, title: c.window.title,
                                   displayID: screen.displayKey,
                                   displayIndex: screens.firstIndex(of: screen) ?? 0,
                                   zone: Zone(frame: c.frame, in: screen.axVisibleFrame))
        }
        return Workspace(id: id, name: name, windows: windows)
    }

    /// Progress of one restore, carried across retries.
    @MainActor private final class Progress {
        var pending: Set<Int>
        var placed = Set<WindowKey>()
        var attempts = 0

        init(pending: Set<Int>) { self.pending = pending }
    }

    func restore(_ workspace: Workspace) {
        restoreTimer?.invalidate()
        let progress = Progress(pending: Set(workspace.windows.indices))

        if Settings.launchAppsForWorkspaces {
            launchMissingApps(Set(workspace.windows.map(\.bundleID)))
        }

        arrange(workspace, progress)
        guard !progress.pending.isEmpty else { return }

        // Freshly launched apps need a moment for their windows to appear.
        restoreTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                progress.attempts += 1
                self?.arrange(workspace, progress)
                if progress.pending.isEmpty || progress.attempts >= 20 { timer.invalidate() }
            }
        }
    }

    private func launchMissingApps(_ bundleIDs: Set<String>) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for bundleID in bundleIDs.subtracting(running) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    private struct OpenWindow {
        let window: AXWindow
        let bundleID: String
        let title: String
    }

    private func arrange(_ workspace: Workspace, _ progress: Progress) {
        let wanted = Set(progress.pending.map { workspace.windows[$0].bundleID })
        var open: [OpenWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, wanted.contains(bundleID) else { continue }
            for window in AXWindow.windows(of: app.processIdentifier)
            where window.isStandard && !progress.placed.contains(WindowKey(window)) {
                open.append(OpenWindow(window: window, bundleID: bundleID, title: window.title))
            }
        }

        let indices = progress.pending.sorted()
        let saved = indices.map { workspace.windows[$0] }
        let pairs = WorkspaceMatcher.assign(saved: saved, open: open, bundleID: \.bundleID, title: \.title)

        var arranged: [AXWindow] = []
        for pair in pairs {
            let entry = saved[pair.saved]
            let window = open[pair.open].window
            let screen = screen(for: entry)
            if window.isMinimized {
                AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            SnapEngine.shared.forget(window)
            window.setFrame(entry.zone.rect(in: screen.axVisibleFrame))
            progress.placed.insert(WindowKey(window))
            progress.pending.remove(indices[pair.saved])
            arranged.append(window)
        }

        // Saved order is front to back: raise back to front so the first ends on top.
        guard !arranged.isEmpty else { return }
        for window in arranged.reversed() {
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
        arranged.first?.focus()
    }

    private func screen(for entry: WorkspaceWindow) -> NSScreen {
        let screens = NSScreen.screens
        if let id = entry.displayID, let match = screens.first(where: { $0.displayKey == id }) { return match }
        if entry.displayIndex < screens.count { return screens[entry.displayIndex] }
        return NSScreen.main ?? screens[0]
    }

    // MARK: UI helpers

    /// Asks for a name; returns nil if cancelled.
    static func promptForName(title: String, defaultName: String) -> String? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.tr("workspace.prompt.info")
        alert.addButton(withTitle: L10n.tr("common.save"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultName : name
    }
}
