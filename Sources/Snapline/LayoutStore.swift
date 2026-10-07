import AppKit
import SnaplineCore

/// Persists custom layouts, workspaces and the active layout of each display.
/// JSON lives in ~/Library/Application Support/Snapline.
@MainActor
final class LayoutStore {
    static let shared = LayoutStore()
    static let didChange = Notification.Name("SnaplineLayoutStoreDidChange")

    private(set) var customLayouts: [CustomLayout] = []
    private(set) var workspaces: [Workspace] = []

    private let directory: URL
    private var layoutsURL: URL { directory.appendingPathComponent("layouts.json") }
    private var workspacesURL: URL { directory.appendingPathComponent("workspaces.json") }
    private let activeKey = "activeLayoutByDisplay"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Snapline", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        customLayouts = load([CustomLayout].self, from: layoutsURL) ?? []
        workspaces = load([Workspace].self, from: workspacesURL) ?? []
    }

    // MARK: Layouts

    func layouts(for screen: NSScreen) -> [Layout] {
        LayoutCatalog.layouts(for: screen.screenClass, custom: customLayouts.map(\.layout))
    }

    func activeLayoutIndex(for screen: NSScreen) -> Int {
        let list = layouts(for: screen)
        let active = (UserDefaults.standard.dictionary(forKey: activeKey) as? [String: String])?[screen.displayKey]
        return list.firstIndex { $0.id == active } ?? 0
    }

    func activeLayout(for screen: NSScreen) -> Layout {
        layouts(for: screen)[activeLayoutIndex(for: screen)]
    }

    func setActiveLayout(_ layout: Layout, for screen: NSScreen) {
        var map = UserDefaults.standard.dictionary(forKey: activeKey) as? [String: String] ?? [:]
        map[screen.displayKey] = layout.id
        UserDefaults.standard.set(map, forKey: activeKey)
        notify()
    }

    func custom(id: String) -> CustomLayout? { customLayouts.first { $0.id == id } }

    func upsert(_ layout: CustomLayout) {
        if let i = customLayouts.firstIndex(where: { $0.id == layout.id }) {
            customLayouts[i] = layout
        } else {
            customLayouts.append(layout)
        }
        save(customLayouts, to: layoutsURL)
        notify()
    }

    func deleteLayout(id: String) {
        customLayouts.removeAll { $0.id == id }
        save(customLayouts, to: layoutsURL)
        notify()
    }

    func moveLayout(id: String, by offset: Int) {
        guard let i = customLayouts.firstIndex(where: { $0.id == id }) else { return }
        let j = min(max(i + offset, 0), customLayouts.count - 1)
        guard i != j else { return }
        customLayouts.swapAt(i, j)
        save(customLayouts, to: layoutsURL)
        notify()
    }

    // MARK: Workspaces

    func upsert(_ workspace: Workspace) {
        if let i = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[i] = workspace
        } else {
            workspaces.append(workspace)
        }
        save(workspaces, to: workspacesURL)
        notify()
    }

    func deleteWorkspace(id: String) {
        workspaces.removeAll { $0.id == id }
        save(workspaces, to: workspacesURL)
        notify()
    }

    // MARK: Persistence

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("Snapline: could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Snapline: could not write \(url.lastPathComponent): \(error)")
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Survives reboots and re-plugging, unlike the display ID.
    var displayKey: String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            return string
        }
        return "display-\(displayID)"
    }
}
