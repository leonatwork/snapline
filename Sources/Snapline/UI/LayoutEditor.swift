import AppKit
import SnaplineCore

/// "Edit layouts…": list of layouts on the left, monitor-shaped editor on the right.
@MainActor
final class LayoutEditorController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let shared = LayoutEditorController()

    private enum Row {
        case header(String)
        case layout(Layout, number: Int)
    }

    private let table = NSTableView()
    private let editor = ZoneEditorView()
    private let nameField = NSTextField()
    private let screenPopup = NSPopUpButton()
    private let activeButton = NSButton()
    private let duplicateButton = NSButton()
    private let deleteButton = NSButton()
    private let upButton = NSButton()
    private let downButton = NSButton()
    private let hint = NSTextField(labelWithString: "")

    private var rows: [Row] = []
    private var selectedID: String?
    private var store: LayoutStore { .shared }

    private var screen: NSScreen {
        let screens = NSScreen.screens
        let i = screenPopup.indexOfSelectedItem
        return i >= 0 && i < screens.count ? screens[i] : (NSScreen.main ?? screens[0])
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 640),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Snapline – Layouts"
        window.minSize = NSSize(width: 820, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        NotificationCenter.default.addObserver(forName: LayoutStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        for name in [Settings.shortcutsDidChange, ShortcutLabels.didChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present(selecting layoutID: String? = nil) {
        reloadScreens()
        if let layoutID { selectedID = layoutID }
        reload()
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Sidebar.
        let column = NSTableColumn(identifier: .init("layout"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.dataSource = self
        table.delegate = self
        table.rowSizeStyle = .custom
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
        addButton.bezelStyle = .rounded
        let addMenu = addButton.menu!
        addMenu.addItem(withTitle: L10n.tr("editor.newLayout"), action: nil, keyEquivalent: "")
        for (index, (title, tree)) in Self.templates.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(addFromTemplate(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            item.representedObject = TreeBox(tree)
            addMenu.addItem(item)
        }

        configure(duplicateButton, title: L10n.tr("editor.duplicate"), action: #selector(duplicate))
        configure(deleteButton, title: L10n.tr("common.delete"), action: #selector(deleteLayout))
        configure(upButton, symbol: "chevron.up", action: #selector(moveLayoutUp))
        configure(downButton, symbol: "chevron.down", action: #selector(moveLayoutDown))

        let sidebarButtons = NSStackView(views: [addButton, duplicateButton, deleteButton, upButton, downButton])
        sidebarButtons.spacing = 6

        // Header.
        nameField.placeholderString = L10n.tr("editor.namePlaceholder")
        nameField.font = .systemFont(ofSize: 15, weight: .semibold)
        nameField.delegate = self
        screenPopup.target = self
        screenPopup.action = #selector(screenChanged)
        activeButton.bezelStyle = .rounded
        activeButton.target = self
        activeButton.action = #selector(makeActive)

        let monitorLabel = NSTextField(labelWithString: L10n.tr("editor.display"))
        let header = NSStackView(views: [nameField, monitorLabel, screenPopup, activeButton])
        header.spacing = 10
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2

        editor.onChange = { [weak self] tree in self?.treeChanged(tree) }

        for v in [scroll, sidebarButtons, header, editor, hint] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.widthAnchor.constraint(equalToConstant: 270),
            scroll.bottomAnchor.constraint(equalTo: sidebarButtons.topAnchor, constant: -10),
            sidebarButtons.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            sidebarButtons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            editor.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            editor.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: -8),
            editor.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            editor.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -8),

            hint.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func configure(_ button: NSButton, title: String? = nil, symbol: String? = nil, action: Selector) {
        button.bezelStyle = .rounded
        if let title { button.title = title }
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.title = ""
        }
        button.target = self
        button.action = action
    }

    private func reloadScreens() {
        let current = screenPopup.indexOfSelectedItem
        screenPopup.removeAllItems()
        for s in NSScreen.screens {
            let ratio: String
            switch s.screenClass {
            case .superWide: ratio = "32:9"
            case .wide: ratio = "21:9"
            case .standard: ratio = "16:9"
            case .portrait: ratio = L10n.tr("editor.portrait")
            }
            screenPopup.addItem(withTitle: "\(s.localizedName) (\(ratio))")
        }
        let cursorScreen = Screens.screen(containingAX: Screens.cursorAX)
        let preferred = current >= 0 && current < NSScreen.screens.count ? current
            : NSScreen.screens.firstIndex { $0 == cursorScreen } ?? 0
        screenPopup.selectItem(at: preferred)
    }

    // MARK: Data

    private func reload() {
        guard window != nil else { return }
        let all = store.layouts(for: screen)
        let custom = all.enumerated().filter { $0.element.isCustom }
        let builtIn = all.enumerated().filter { !$0.element.isCustom }

        rows = [.header(L10n.tr("editor.customLayouts"))]
        rows += custom.map { .layout($0.element, number: $0.offset + 1) }
        rows.append(.header(L10n.tr("editor.templates")))
        rows += builtIn.map { .layout($0.element, number: $0.offset + 1) }

        table.reloadData()
        if selectedID == nil || !all.contains(where: { $0.id == selectedID }) {
            selectedID = (custom.first ?? builtIn.first)?.element.id
        }
        if let row = rows.firstIndex(where: { if case .layout(let l, _) = $0 { return l.id == selectedID } else { return false } }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
        updateDetail()
    }

    private var selectedLayout: Layout? {
        store.layouts(for: screen).first { $0.id == selectedID }
    }

    private func updateDetail() {
        guard let layout = selectedLayout else { return }
        let custom = store.custom(id: layout.id)
        editor.show(tree: custom?.root, zones: layout.zones, editable: custom != nil,
                    screenSize: screen.frame.size)

        nameField.stringValue = layout.displayName
        nameField.isEditable = custom != nil
        nameField.isBezeled = custom != nil
        nameField.drawsBackground = custom != nil

        let isActive = store.activeLayout(for: screen).id == layout.id
        activeButton.title = isActive ? L10n.tr("editor.activeOnDisplay") : L10n.tr("editor.makeActive")
        activeButton.isEnabled = !isActive
        deleteButton.isEnabled = custom != nil
        upButton.isEnabled = custom != nil
        downButton.isEnabled = custom != nil

        let number = (store.layouts(for: screen).firstIndex { $0.id == layout.id } ?? 0) + 1
        let label = ShortcutLabels.layout(number)
        let shortcut = label.isEmpty ? "" : L10n.tr("editor.shortcutActivates", label)
        hint.stringValue = custom != nil
            ? L10n.tr("editor.hint.custom") + " " + shortcut
            : L10n.tr("editor.hint.builtIn") + " " + shortcut
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 26 }
        return 54
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .layout = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title.uppercased())
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        case .layout(let layout, let number):
            let isActive = store.activeLayout(for: screen).id == layout.id
            return LayoutRowView(layout: layout, number: number, active: isActive, aspect: screen.frame.width / screen.frame.height)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard row >= 0, case .layout(let layout, _) = rows[row] else { return }
        window?.makeFirstResponder(nil)
        selectedID = layout.id
        updateDetail()
    }

    // MARK: Actions

    private final class TreeBox {
        let tree: ZoneNode
        init(_ tree: ZoneNode) { self.tree = tree }
    }

    private static let templates: [(String, ZoneNode)] = {
        func cols(_ widths: [CGFloat]) -> ZoneNode {
            ZoneNode.from(zones: Layout.columns("", "", widths).zones) ?? .leaf
        }
        func grid(_ c: Int, _ r: Int) -> ZoneNode {
            ZoneNode.from(zones: Layout.grid("", "", columns: c, rows: r).zones) ?? .leaf
        }
        return [
            // Index 0 is the empty template, see addFromTemplate.
            (L10n.tr("editor.template.empty"), .leaf),
            (L10n.tr("editor.template.columns", 2), cols([1, 1])),
            (L10n.tr("editor.template.columns", 3), cols([1, 1, 1])),
            (L10n.tr("editor.template.columns", 4), cols([1, 1, 1, 1])),
            ("20 · 60 · 20", cols([1, 3, 1])),
            ("25 · 50 · 25", cols([1, 2, 1])),
            (L10n.tr("editor.template.grid", 2, 2), grid(2, 2)),
            (L10n.tr("editor.template.grid", 3, 2), grid(3, 2)),
        ]
    }()

    @objc private func addFromTemplate(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? TreeBox else { return }
        let layout = CustomLayout(id: UUID().uuidString, name: sender.tag == 0 ? L10n.tr("editor.newLayout") : sender.title,
                                  root: box.tree)
        selectedID = layout.id
        store.upsert(layout)
        window?.makeFirstResponder(nameField)
    }

    @objc private func duplicate() {
        guard let layout = selectedLayout else { return }
        let root = store.custom(id: layout.id)?.root ?? ZoneNode.from(zones: layout.zones) ?? .leaf
        let copy = CustomLayout(id: UUID().uuidString, name: L10n.tr("editor.copyName", layout.displayName), root: root)
        selectedID = copy.id
        store.upsert(copy)
    }

    @objc private func deleteLayout() {
        guard let layout = selectedLayout, layout.isCustom else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("editor.deleteConfirm", layout.displayName)
        alert.addButton(withTitle: L10n.tr("common.delete"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        selectedID = nil
        store.deleteLayout(id: layout.id)
    }

    @objc private func moveLayoutUp() { if let id = selectedID { store.moveLayout(id: id, by: -1) } }
    @objc private func moveLayoutDown() { if let id = selectedID { store.moveLayout(id: id, by: 1) } }

    @objc private func makeActive() {
        guard let layout = selectedLayout else { return }
        store.setActiveLayout(layout, for: screen)
    }

    @objc private func screenChanged() {
        reload()
    }

    private func treeChanged(_ tree: ZoneNode) {
        guard let id = selectedID, var custom = store.custom(id: id) else { return }
        custom.root = tree
        store.upsert(custom)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let id = selectedID, var custom = store.custom(id: id) else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != custom.name else { return }
        custom.name = name
        store.upsert(custom)
    }
}

/// Sidebar row: miniature, name, shortcut number and active marker.
@MainActor
private final class LayoutRowView: NSView {
    private let layout: Layout
    private let aspect: CGFloat

    init(layout: Layout, number: Int, active: Bool, aspect: CGFloat) {
        self.layout = layout
        self.aspect = aspect
        super.init(frame: .zero)

        let name = NSTextField(labelWithString: layout.displayName)
        name.font = .systemFont(ofSize: 13, weight: active ? .semibold : .regular)
        name.lineBreakMode = .byTruncatingTail
        let detail = NSTextField(labelWithString: ShortcutLabels.layout(number) + (active ? "  ·  " + L10n.tr("editor.activeTag") : ""))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = active ? .controlAccentColor : .secondaryLabelColor

        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 96),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let width: CGFloat = 84
        let height = min(40, width / aspect)
        let tile = CGRect(x: 4, y: (bounds.height - height) / 2, width: width, height: height)
        for zone in layout.zones {
            let r = CGRect(x: tile.minX + zone.x * tile.width, y: tile.minY + zone.y * tile.height,
                           width: zone.width * tile.width, height: zone.height * tile.height).insetBy(dx: 1, dy: 1)
            NSColor.labelColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5).fill()
        }
    }
}
