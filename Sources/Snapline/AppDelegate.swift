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
        appMenu.addItem(NSMenuItem(title: "Fenster schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem(title: "Snapline beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(NSMenuItem(title: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
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
            menu.addItem(item("⚠️ Bedienungshilfen-Zugriff erteilen…", #selector(openAccessibilitySettings)))
        } else if !tap.isInstalled {
            menu.addItem(item("⚠️ Event Tap nicht aktiv – Snapline neu starten", #selector(relaunch)))
        }
        if NativeTiling.conflicts && (Settings.dragSnap || Settings.optionDragZones) {
            menu.addItem(item("⚠️ macOS-Kacheln ist noch aktiv – deaktivieren…", #selector(openTilingSettings)))
        }
        let thumbs = ThumbnailProvider.shared
        if Settings.livePreviews && !thumbs.isGranted {
            menu.addItem(item("⚠️ Bildschirmaufnahme für Live-Vorschau erlauben…", #selector(openScreenCaptureSettings)))
        } else if Settings.livePreviews && thumbs.needsRestart {
            menu.addItem(item("↻ Neu starten, um Live-Vorschau zu aktivieren", #selector(relaunch)))
        }
        menu.addItem(.separator())

        // Layouts.
        let layoutsItem = item("Snap-Layouts für aktives Fenster", #selector(showLayouts))
        layoutsItem.keyEquivalent = "z"
        layoutsItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(layoutsItem)
        for screen in NSScreen.screens {
            menu.addItem(submenu(NSScreen.screens.count > 1 ? "Aktives Layout – \(screen.localizedName)" : "Aktives Layout",
                                 activeLayoutMenu(for: screen)))
        }
        menu.addItem(item("Layouts bearbeiten…", #selector(openEditor)))
        menu.addItem(.separator())

        // Workspaces.
        menu.addItem(submenu("Arbeitsbereiche", workspacesMenu()))
        menu.addItem(.separator())

        // Behaviour.
        let behaviour = NSMenu()
        behaviour.addItem(toggle("Fenster an Ränder ziehen (Aero Snap)", Settings.dragSnap, #selector(toggleDragSnap)))
        behaviour.addItem(toggle("\(Settings.zoneModifier.symbol) + Ziehen: in Zonen des aktiven Layouts", Settings.optionDragZones, #selector(toggleOptionZones)))
        behaviour.addItem(toggle("Snap-Layouts beim Hover über grünen Knopf", Settings.hoverFlyout, #selector(toggleHover)))
        behaviour.addItem(toggle("macOS-Menü am grünen Knopf unterdrücken", Settings.suppressNativeMenu, #selector(toggleSuppress)))
        behaviour.addItem(toggle("Snap Assist", Settings.snapAssist, #selector(toggleAssist)))
        behaviour.addItem(toggle("Live-Vorschau in Snap Assist", Settings.livePreviews, #selector(togglePreviews)))
        behaviour.addItem(toggle("Ursprungsgröße beim Wegziehen", Settings.restoreOnDrag, #selector(toggleRestore)))
        behaviour.addItem(toggle("Arbeitsbereiche: fehlende Apps starten", Settings.launchAppsForWorkspaces, #selector(toggleLaunchApps)))
        menu.addItem(submenu("Verhalten", behaviour))

        let modifierMenu = NSMenu()
        for (modifier, title) in [(ZoneModifier.command, "⌘ Befehl"), (.option, "⌥ Wahl"), (.shift, "⇧ Umschalt (wie FancyZones)")] {
            let i = toggle(title, Settings.zoneModifier == modifier, #selector(setZoneModifier(_:)))
            i.representedObject = modifier.rawValue
            modifierMenu.addItem(i)
        }
        menu.addItem(submenu("Taste für Zonen-Ziehen", modifierMenu))

        let gapMenu = NSMenu()
        for gap in [0, 4, 8, 12, 16] {
            let i = toggle(gap == 0 ? "Kein Abstand" : "\(gap) pt", Int(Settings.gap) == gap, #selector(setGap(_:)))
            i.tag = gap
            gapMenu.addItem(i)
        }
        menu.addItem(submenu("Abstand zwischen Fenstern", gapMenu))

        let columnsMenu = NSMenu()
        for (count, title) in [(2, "Hälften"), (3, "Drittel"), (4, "Viertel")] {
            let i = toggle(title, Settings.superWideColumns == count, #selector(setColumns(_:)))
            i.tag = count
            columnsMenu.addItem(i)
        }
        menu.addItem(submenu("Rand-Spalten auf 32:9-Monitoren", columnsMenu))

        let shortcuts = NSMenu()
        for line in [
            "⌃⌥Z  Snap-Layouts, dann Ziffer für Layout und Zone",
            "⌃⌥1…9  Aktives Layout des Monitors wählen",
            "⌃⌥⇧1…9  Arbeitsbereich wiederherstellen",
            "⌃⌥←/→  Spalte links/rechts, weiter zum nächsten Monitor",
            "⌃⌥↑  Maximieren / obere Hälfte der Spalte",
            "⌃⌥↓  Wiederherstellen / untere Hälfte / Minimieren",
            "\(Settings.zoneModifier.symbol) + Ziehen  In Zonen des aktiven Layouts ablegen",
            "   … Mausrad / 1–9 / Tab  Layout wechseln",
            "   … \(Settings.zoneModifier.spanSymbol)  mehrere Zonen verbinden · Esc  abbrechen",
            "Ziehen an Rand/Ecke  Spalte bzw. halbe Spalte",
            "Ziehen oben Mitte  Snap-Leiste mit Layouts",
        ] {
            let i = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            i.isEnabled = false
            shortcuts.addItem(i)
        }
        menu.addItem(submenu("Tastenkürzel & Gesten", shortcuts))
        menu.addItem(.separator())

        menu.addItem(toggle("Bei Anmeldung starten", Settings.launchAtLogin, #selector(toggleLaunchAtLogin)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Snapline beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func activeLayoutMenu(for screen: NSScreen) -> NSMenu {
        let menu = NSMenu()
        let layouts = LayoutStore.shared.layouts(for: screen)
        let active = LayoutStore.shared.activeLayoutIndex(for: screen)
        for (i, layout) in layouts.enumerated() {
            let entry = toggle(layout.name, i == active, #selector(selectActiveLayout(_:)))
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
        menu.addItem(item("Aktuelle Anordnung speichern…", #selector(saveWorkspace)))
        let all = LayoutStore.shared.workspaces
        if !all.isEmpty { menu.addItem(.separator()) }
        for (i, ws) in all.enumerated() {
            let sub = NSMenu()
            let restore = item("Wiederherstellen", #selector(restoreWorkspace(_:)))
            restore.representedObject = ws.id
            sub.addItem(restore)
            let overwrite = item("Mit aktueller Anordnung überschreiben", #selector(overwriteWorkspace(_:)))
            overwrite.representedObject = ws.id
            sub.addItem(overwrite)
            let rename = item("Umbenennen…", #selector(renameWorkspace(_:)))
            rename.representedObject = ws.id
            sub.addItem(rename)
            sub.addItem(.separator())
            let delete = item("Löschen", #selector(deleteWorkspace(_:)))
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
        let name = "Arbeitsbereich \(LayoutStore.shared.workspaces.count + 1)"
        // Capture before the alert takes focus.
        let snapshot = workspaces.capture(name: name)
        guard let chosen = WorkspaceController.promptForName(title: "Arbeitsbereich speichern", defaultName: name) else { return }
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
              let name = WorkspaceController.promptForName(title: "Arbeitsbereich umbenennen", defaultName: ws.name)
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
