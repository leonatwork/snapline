import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let preview = PreviewOverlay()
    private let assist = SnapAssistController()
    private lazy var flyouts = FlyoutController(assist: assist)
    private lazy var drag = DragController(flyouts: flyouts, preview: preview, assist: assist)
    private lazy var hover = HoverController(flyouts: flyouts)
    private lazy var keyboard = KeyboardController(flyouts: flyouts, assist: assist)
    private var started = false
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        setUpStatusItem()
        keyboard.start()

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
        drag.start()
        hover.start()
    }

    // MARK: Menu

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

        let header = NSMenuItem(title: "Snapline", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if !AXIsProcessTrusted() {
            menu.addItem(item("⚠️ Bedienungshilfen-Zugriff erteilen…", #selector(openAccessibilitySettings)))
        }
        if NativeTiling.conflicts && Settings.dragSnap {
            menu.addItem(item("⚠️ macOS-Kacheln am Rand ist aktiv – deaktivieren…", #selector(openTilingSettings)))
        }
        menu.addItem(.separator())

        let layouts = item("Snap-Layouts für aktives Fenster", #selector(showLayouts))
        layouts.keyEquivalent = "z"
        layouts.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(layouts)
        menu.addItem(.separator())

        menu.addItem(toggle("Fenster an Ränder ziehen (Aero Snap)", Settings.dragSnap, #selector(toggleDragSnap)))
        menu.addItem(toggle("Snap-Layouts beim Hover über grünen Knopf", Settings.hoverFlyout, #selector(toggleHover)))
        menu.addItem(toggle("Snap Assist", Settings.snapAssist, #selector(toggleAssist)))
        menu.addItem(toggle("Ursprungsgröße beim Wegziehen", Settings.restoreOnDrag, #selector(toggleRestore)))
        menu.addItem(.separator())

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
        menu.addItem(submenu("Spalten auf 32:9-Monitoren", columnsMenu))

        let shortcuts = NSMenu()
        for line in [
            "⌃⌥Z  Snap-Layouts (wie Win+Z)",
            "⌃⌥←/→  Spalte links/rechts, weiter zum nächsten Monitor",
            "⌃⌥↑  Maximieren / obere Hälfte der Spalte",
            "⌃⌥↓  Wiederherstellen / untere Hälfte / Minimieren",
            "Ziehen an Rand/Ecke  Spalte bzw. halbe Spalte",
            "Ziehen an unteren Rand  Spalte unter dem Cursor",
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

    @objc private func toggleDragSnap() { Settings.dragSnap.toggle() }
    @objc private func toggleHover() { Settings.hoverFlyout.toggle() }
    @objc private func toggleAssist() { Settings.snapAssist.toggle() }
    @objc private func toggleRestore() { Settings.restoreOnDrag.toggle() }
    @objc private func toggleLaunchAtLogin() { Settings.launchAtLogin.toggle() }
    @objc private func setGap(_ sender: NSMenuItem) { Settings.gap = CGFloat(sender.tag) }
    @objc private func setColumns(_ sender: NSMenuItem) { Settings.superWideColumns = sender.tag }
    @objc private func openTilingSettings() { NativeTiling.openSettings() }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
