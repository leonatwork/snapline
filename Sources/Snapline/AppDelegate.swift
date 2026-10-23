import AppKit
import ApplicationServices
import SnaplineCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let preview = PreviewOverlay()
    private let zoneOverlay = ZoneOverlay()
    private let assist = SnapAssistController()
    private let tap = EventTap()
    private let workspaces = WorkspaceController()
    private lazy var flyouts = FlyoutController(assist: assist)
    private lazy var drag = DragController(flyouts: flyouts, preview: preview, zoneOverlay: zoneOverlay, assist: assist)
    private lazy var hover = HoverController(flyouts: flyouts)
    private lazy var keyboard = KeyboardController(flyouts: flyouts, assist: assist, zoneOverlay: zoneOverlay,
                                                   workspaces: workspaces)
    private var started = false
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        installMainMenu()
        setUpStatusItem()
        keyboard.start()
        ThumbnailProvider.shared.refreshPermission()

        if AXIsProcessTrusted() {
            startMonitors()
        } else {
            requestAccessibility()
        }
    }

    // MARK: Permissions

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.startMonitors()
            }
        }
    }

    private func startMonitors() {
        guard !started else { return }
        started = true
        tap.install()
        drag.start(tap: tap)
        hover.start(tap: tap)
    }

    // MARK: Menus

    /// Accessory apps still need an Edit menu for ⌘C/⌘V/⌘A in text fields.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L10n.tr("mainMenu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.tr("mainMenu.edit"))
        edit.addItem(NSMenuItem(title: L10n.tr("mainMenu.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: L10n.tr("mainMenu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: L10n.tr("mainMenu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: L10n.tr("mainMenu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: L10n.tr("mainMenu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Snapline")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        ThumbnailProvider.shared.refreshPermission()

        let header = NSMenuItem(title: "Snapline", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Warnings first, so they can't be missed.
        if !AXIsProcessTrusted() {
            menu.addItem(item(L10n.tr("menu.warning.accessibility"), #selector(openAccessibilitySettings)))
        } else if !tap.isInstalled {
            menu.addItem(item(L10n.tr("menu.warning.eventTap"), #selector(relaunch)))
        }
        let windowManagerWarnings = NativeTiling.snapshot.warnings(
            dragSnapEnabled: Settings.dragSnap, zoneDragEnabled: Settings.optionDragZones,
            zoneModifierIsOption: Settings.zoneModifier == .option)
        if windowManagerWarnings.stageManager {
            menu.addItem(item(L10n.tr("menu.warning.stageManager"), #selector(openTilingSettings)))
        }
        if windowManagerWarnings.nativeTiling {
            menu.addItem(item(L10n.tr("menu.warning.nativeTiling"), #selector(openTilingSettings)))
            menu.addItem(item(L10n.tr("menu.disableNativeTiling"), #selector(disableNativeTiling)))
        }
        let thumbs = ThumbnailProvider.shared
        if Settings.livePreviews && !thumbs.isGranted {
            menu.addItem(item(L10n.tr("menu.warning.screenRecording"), #selector(openScreenCaptureSettings)))
        } else if Settings.livePreviews && thumbs.needsRestart {
            menu.addItem(item(L10n.tr("menu.restartForPreviews"), #selector(relaunch)))
        }
        menu.addItem(.separator())

        // Layouts.
        let layoutsItem = item(L10n.tr("menu.showLayouts"), #selector(showLayouts))
        layoutsItem.keyEquivalent = "z"
        layoutsItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(layoutsItem)
        for screen in NSScreen.screens {
            menu.addItem(submenu(NSScreen.screens.count > 1
                                    ? L10n.tr("menu.activeLayoutOnScreen", screen.localizedName)
                                    : L10n.tr("menu.activeLayout"),
                                 activeLayoutMenu(for: screen)))
        }
        menu.addItem(item(L10n.tr("menu.editLayouts"), #selector(openEditor)))
        menu.addItem(.separator())

        // Workspaces.
        menu.addItem(submenu(L10n.tr("menu.workspaces"), workspacesMenu()))
        menu.addItem(.separator())

        // Capture the active app now: menu actions must not use the app that
        // happens to be frontmost after the menu has taken focus.
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != getpid(), let bundleID = app.bundleIdentifier {
            let title = Settings.appExclusions.contains(bundleID: bundleID)
                ? L10n.tr("menu.enableForApp", app.localizedName ?? bundleID)
                : L10n.tr("menu.disableForApp", app.localizedName ?? bundleID)
            let entry = item(title, #selector(toggleAppExclusion(_:)))
            entry.representedObject = bundleID
            menu.addItem(entry)
        }
        menu.addItem(submenu(L10n.tr("menu.excludedApps"), excludedAppsMenu()))
        menu.addItem(.separator())

        // Behaviour.
        let behaviour = NSMenu()
        behaviour.addItem(toggle(L10n.tr("behavior.dragSnap"), Settings.dragSnap, #selector(toggleDragSnap)))
        behaviour.addItem(toggle(L10n.tr("behavior.zoneDrag", Settings.zoneModifier.symbol), Settings.optionDragZones, #selector(toggleOptionZones)))
        behaviour.addItem(toggle(L10n.tr("behavior.hoverFlyout"), Settings.hoverFlyout, #selector(toggleHover)))
        behaviour.addItem(toggle(L10n.tr("behavior.suppressNativeMenu"), Settings.suppressNativeMenu, #selector(toggleSuppress)))
        behaviour.addItem(toggle(L10n.tr("behavior.snapAssist"), Settings.snapAssist, #selector(toggleAssist)))
        behaviour.addItem(toggle(L10n.tr("behavior.livePreviews"), Settings.livePreviews, #selector(togglePreviews)))
        behaviour.addItem(toggle(L10n.tr("behavior.restoreOnDrag"), Settings.restoreOnDrag, #selector(toggleRestore)))
        behaviour.addItem(toggle(L10n.tr("behavior.launchMissingApps"), Settings.launchAppsForWorkspaces, #selector(toggleLaunchApps)))
        menu.addItem(submenu(L10n.tr("menu.behavior"), behaviour))

        let modifierMenu = NSMenu()
        for (modifier, title) in [(ZoneModifier.command, L10n.tr("zoneKey.command")), (.option, L10n.tr("zoneKey.option")),
                                  (.shift, L10n.tr("zoneKey.shift"))] {
            let i = toggle(title, Settings.zoneModifier == modifier, #selector(setZoneModifier(_:)))
            i.representedObject = modifier.rawValue
            modifierMenu.addItem(i)
        }
        menu.addItem(submenu(L10n.tr("menu.zoneKey"), modifierMenu))

        let gapMenu = NSMenu()
        for gap in [0, 4, 8, 12, 16] {
            let i = toggle(gap == 0 ? L10n.tr("gap.none") : L10n.tr("gap.points", gap), Int(Settings.gap) == gap, #selector(setGap(_:)))
            i.tag = gap
            gapMenu.addItem(i)
        }
        menu.addItem(submenu(L10n.tr("menu.gap"), gapMenu))

        let columnsMenu = NSMenu()
        for (count, title) in [(2, L10n.tr("columns.halves")), (3, L10n.tr("columns.thirds")), (4, L10n.tr("columns.quarters"))] {
            let i = toggle(title, Settings.superWideColumns == count, #selector(setColumns(_:)))
            i.tag = count
            columnsMenu.addItem(i)
        }
        menu.addItem(submenu(L10n.tr("menu.edgeColumns"), columnsMenu))

        let shortcuts = NSMenu()
        for line in [
            L10n.tr("shortcut.flyout"),
            L10n.tr("shortcut.activeLayout"),
            L10n.tr("shortcut.workspace"),
            L10n.tr("shortcut.leftRight"),
            L10n.tr("shortcut.up"),
            L10n.tr("shortcut.down"),
            L10n.tr("shortcut.zoneDrag", Settings.zoneModifier.symbol),
            L10n.tr("shortcut.zoneDragSwitch"),
            L10n.tr("shortcut.zoneDragSpan", Settings.zoneModifier.spanSymbol),
            L10n.tr("shortcut.edgeDrag"),
            L10n.tr("shortcut.topDrag"),
        ] {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            i.isEnabled = false
            shortcuts.addItem(i)
        }
        menu.addItem(submenu(L10n.tr("menu.shortcuts"), shortcuts))
        menu.addItem(.separator())

        menu.addItem(toggle(L10n.tr("menu.launchAtLogin"), Settings.launchAtLogin, #selector(toggleLaunchAtLogin)))
        menu.addItem(submenu(L10n.tr("menu.moreApps"), moreAppsMenu()))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func excludedAppsMenu() -> NSMenu {
        let menu = NSMenu()
        for bundleID in Settings.appExclusions.bundleIDs {
            let app = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier?.lowercased() == bundleID.lowercased()
            }
            let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let bundle = url.flatMap { Bundle(url: $0) }
            let name = app?.localizedName
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? bundleID
            let entry = item(name, #selector(removeAppExclusion(_:)))
            entry.representedObject = bundleID
            entry.toolTip = bundleID
            let icon = app?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            entry.image = icon?.copy() as? NSImage
            entry.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(entry)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: L10n.tr("menu.excludedApps.empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        return menu
    }

    private func activeLayoutMenu(for screen: NSScreen) -> NSMenu {
        let menu = NSMenu()
        let layouts = LayoutStore.shared.layouts(for: screen)
        let active = LayoutStore.shared.activeLayoutIndex(for: screen)
        for (i, layout) in layouts.enumerated() {
            let entry = toggle(layout.displayName, i == active, #selector(selectActiveLayout(_:)))
            entry.representedObject = ActiveLayoutChoice(screen: screen, layout: layout, number: i + 1, count: layouts.count)
            if i < 9 {
                entry.keyEquivalent = "\(i + 1)"
                entry.keyEquivalentModifierMask = [.control, .option]
            }
            menu.addItem(entry)
        }
        return menu
    }

    private func workspacesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(L10n.tr("workspace.saveCurrent"), #selector(saveWorkspace)))
        let all = LayoutStore.shared.workspaces
        if !all.isEmpty { menu.addItem(.separator()) }
        for (i, ws) in all.enumerated() {
            let sub = NSMenu()
            let restore = item(L10n.tr("workspace.restore"), #selector(restoreWorkspace(_:)))
            restore.representedObject = ws.id
            sub.addItem(restore)
            let overwrite = item(L10n.tr("workspace.overwrite"), #selector(overwriteWorkspace(_:)))
            overwrite.representedObject = ws.id
            sub.addItem(overwrite)
            let rename = item(L10n.tr("workspace.rename"), #selector(renameWorkspace(_:)))
            rename.representedObject = ws.id
            sub.addItem(rename)
            sub.addItem(.separator())
            let delete = item(L10n.tr("common.delete"), #selector(deleteWorkspace(_:)))
            delete.representedObject = ws.id
            sub.addItem(delete)
            let apps = Array(NSOrderedSet(array: ws.windows.map(\.appName))) as? [String] ?? []
            let entry = submenu("\(ws.name)  (\(apps.prefix(4).joined(separator: ", ")))", sub)
            if i < 9 {
                entry.keyEquivalent = "\(i + 1)"
                entry.keyEquivalentModifierMask = [.control, .option, .shift]
            }
            menu.addItem(entry)
        }
        return menu
    }

    /// The other tools of the "I love macOS, but I miss some Windows features" package.
    private func moreAppsMenu() -> NSMenu {
        let menu = NSMenu()
        for app in PackageApps.others {
            let entry = item("\(app.name) – \(L10n.tr(app.descriptionKey))", #selector(openLink(_:)))
            entry.representedObject = app.url
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let all = item(L10n.tr("moreApps.wholePackage"), #selector(openLink(_:)))
        all.representedObject = PackageApps.packageURL
        menu.addItem(all)
        return menu
    }

    private final class ActiveLayoutChoice {
        let screen: NSScreen
        let layout: Layout
        let number: Int
        let count: Int
        init(screen: NSScreen, layout: Layout, number: Int, count: Int) {
            self.screen = screen
            self.layout = layout
            self.number = number
            self.count = count
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let i = item(title, action)
        i.state = on ? .on : .off
        return i
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = menu
        return i
    }

    // MARK: Actions

    @objc private func toggleAppExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        let exclusions = Settings.appExclusions
        Settings.appExclusions = exclusions.contains(bundleID: bundleID)
            ? exclusions.removing(bundleID: bundleID)
            : exclusions.adding(bundleID: bundleID)
        appExclusionsDidChange()
    }

    @objc private func removeAppExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Settings.appExclusions = Settings.appExclusions.removing(bundleID: bundleID)
        appExclusionsDidChange()
    }

    private func appExclusionsDidChange() {
        drag.appExclusionsDidChange()
        flyouts.hide()
        assist.dismiss()
        hover.appExclusionsDidChange()
    }

    @objc private func showLayouts() {
        // Let the menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated { self?.keyboard.showFlyout() }
        }
    }

    @objc private func selectActiveLayout(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ActiveLayoutChoice else { return }
        LayoutStore.shared.setActiveLayout(choice.layout, for: choice.screen)
        zoneOverlay.flash(layout: choice.layout, number: choice.number, count: choice.count, on: choice.screen)
    }

    @objc private func openEditor() { LayoutEditorController.shared.present() }

    @objc private func saveWorkspace() {
        let name = L10n.tr("workspace.defaultName", LayoutStore.shared.workspaces.count + 1)
        // Capture before the alert takes focus.
        let snapshot = workspaces.capture(name: name)
        guard let chosen = WorkspaceController.promptForName(title: L10n.tr("workspace.saveTitle"), defaultName: name) else { return }
        var ws = snapshot
        ws.name = chosen
        LayoutStore.shared.upsert(ws)
    }

    private func workspace(_ sender: NSMenuItem) -> Workspace? {
        guard let id = sender.representedObject as? String else { return nil }
        return LayoutStore.shared.workspaces.first { $0.id == id }
    }

    @objc private func restoreWorkspace(_ sender: NSMenuItem) {
        guard let ws = workspace(sender) else { return }
        workspaces.restore(ws)
    }

    @objc private func overwriteWorkspace(_ sender: NSMenuItem) {
        guard let ws = workspace(sender) else { return }
        LayoutStore.shared.upsert(workspaces.capture(name: ws.name, id: ws.id))
    }

    @objc private func renameWorkspace(_ sender: NSMenuItem) {
        guard var ws = workspace(sender),
              let name = WorkspaceController.promptForName(title: L10n.tr("workspace.renameTitle"), defaultName: ws.name)
        else { return }
        ws.name = name
        LayoutStore.shared.upsert(ws)
    }

    @objc private func deleteWorkspace(_ sender: NSMenuItem) {
        guard let ws = workspace(sender) else { return }
        LayoutStore.shared.deleteWorkspace(id: ws.id)
    }

    @objc private func toggleDragSnap() { Settings.dragSnap.toggle() }
    @objc private func toggleOptionZones() { Settings.optionDragZones.toggle() }
    @objc private func setZoneModifier(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let modifier = ZoneModifier(rawValue: raw) {
            Settings.zoneModifier = modifier
        }
    }
    @objc private func toggleHover() { Settings.hoverFlyout.toggle() }
    @objc private func toggleSuppress() { Settings.suppressNativeMenu.toggle() }
    @objc private func toggleAssist() { Settings.snapAssist.toggle() }
    @objc private func toggleRestore() { Settings.restoreOnDrag.toggle() }
    @objc private func toggleLaunchApps() { Settings.launchAppsForWorkspaces.toggle() }
    @objc private func toggleLaunchAtLogin() { Settings.launchAtLogin.toggle() }
    @objc private func setGap(_ sender: NSMenuItem) { Settings.gap = CGFloat(sender.tag) }
    @objc private func setColumns(_ sender: NSMenuItem) { Settings.superWideColumns = sender.tag }
    @objc private func openTilingSettings() { NativeTiling.openSettings() }

    @objc private func disableNativeTiling() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("tiling.confirm.title")
        let keys = WindowManagerSettings.tilingKeys.map { "• \($0) = false" }.joined(separator: "\n")
        alert.informativeText = L10n.tr("tiling.confirm.info", keys)
        // Cancel is the default; only the explicit second button allows writes.
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        alert.addButton(withTitle: L10n.tr("tiling.confirm.disable"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }

        let saved = NativeTiling.disableTiling(confirmed: true)
        let result = NSAlert()
        result.alertStyle = saved ? .informational : .warning
        result.messageText = L10n.tr("tiling.result.title")
        result.informativeText = saved ? L10n.tr("tiling.result.info") : L10n.tr("tiling.result.failure")
        result.addButton(withTitle: L10n.tr("tiling.result.openSettings"))
        result.runModal()
        NativeTiling.openSettings()
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func togglePreviews() {
        Settings.livePreviews.toggle()
        if Settings.livePreviews { ThumbnailProvider.shared.requestAccessIfNeeded() }
    }

    @objc private func openScreenCaptureSettings() {
        ThumbnailProvider.shared.requestAccessIfNeeded()
        ThumbnailProvider.openSystemSettings()
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
