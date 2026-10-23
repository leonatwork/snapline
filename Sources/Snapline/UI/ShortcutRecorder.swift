import AppKit
import Carbon.HIToolbox
import SnaplineCore

/// A local event monitor records physical keys before AppKit handles menu equivalents.
/// Snapline's global registrations are suspended only while recording.
@MainActor
final class ShortcutRecorderController: NSWindowController, NSWindowDelegate {
    static let shared = ShortcutRecorderController()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var labels: [ShortcutAction: NSTextField] = [:]
    private var recordButtons: [ShortcutAction: NSButton] = [:]
    private var recordingAction: ShortcutAction?
    private var heldModifiers: ShortcutModifiers = []
    private var eventMonitor: Any?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.tr("recorder.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        for name in [Settings.shortcutsDidChange, ShortcutDisplay.inputSourceDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        refresh()
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func button(_ title: String, action: Selector, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.tag = tag
        return button
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let help = NSTextField(wrappingLabelWithString: L10n.tr("recorder.help"))
        stack.addArrangedSubview(help)
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let name = NSTextField(labelWithString: ShortcutDisplay.shared.actionName(action))
            name.widthAnchor.constraint(equalToConstant: 250).isActive = true
            let label = NSTextField(labelWithString: "")
            label.widthAnchor.constraint(equalToConstant: 155).isActive = true
            labels[action] = label
            let record = button(L10n.tr("recorder.record"), action: #selector(record(_:)), tag: index)
            recordButtons[action] = record
            let row = NSStackView(views: [name, label, record,
                button(L10n.tr("common.delete"), action: #selector(clear(_:)), tag: index),
                button(L10n.tr("recorder.reset"), action: #selector(reset(_:)), tag: index)])
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        message.textColor = .secondaryLabelColor
        message.maximumNumberOfLines = 3
        stack.addArrangedSubview(message)
        stack.addArrangedSubview(button(L10n.tr("recorder.resetAll"), action: #selector(resetAll), tag: 0))
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refresh()
        // Translated button titles can be considerably wider than English ones.
        window?.setContentSize(NSSize(width: max(850, stack.fittingSize.width + 40),
                                      height: max(460, stack.fittingSize.height + 40)))
    }

    private func refresh() {
        for action in ShortcutAction.allCases {
            labels[action]?.stringValue = ShortcutDisplay.shared.label(for: action)
            recordButtons[action]?.title = L10n.tr(recordingAction == action ? "recorder.cancel" : "recorder.record")
        }
    }

    @objc private func record(_ sender: NSButton) {
        let action = ShortcutAction.allCases[sender.tag]
        let wasRecording = recordingAction == action
        stopRecording()
        guard !wasRecording else { message.stringValue = ""; return }
        recordingAction = action
        heldModifiers = []
        message.stringValue = L10n.tr(action.isDigitGroup ? "recorder.promptModifiers" : "recorder.promptKey")
        NotificationCenter.default.post(name: KeyboardController.recordingDidChange, object: true)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window, self.recordingAction != nil else { return event }
                self.capture(event)
                return nil
            }
        }
        refresh()
    }

    private func capture(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        let modifiers = ShortcutModifiers(flags: event.modifierFlags)
        if event.type == .flagsChanged {
            guard action.isDigitGroup else { return }
            if !modifiers.isEmpty { heldModifiers.formUnion(modifiers) }
            else if !heldModifiers.isEmpty {
                let captured = heldModifiers
                heldModifiers = []
                save(.digits(captured), for: action)
            }
            return
        }
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            stopRecording()
            message.stringValue = ""
            return
        }
        guard !modifiers.isEmpty else {
            message.stringValue = L10n.tr("recorder.errorModifiers")
            return
        }
        save(action.isDigitGroup ? .digits(modifiers) : .key(Shortcut(keyCode: event.keyCode, modifiers: modifiers)), for: action)
    }

    private func save(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var candidate = Settings.shortcuts
        candidate[action] = binding
        if let error = candidate.validationError(defaultFlyoutKey: ShortcutDisplay.shared.defaultFlyoutKey) {
            switch error {
            case .missingModifiers: message.stringValue = L10n.tr("recorder.errorModifiers")
            case .invalidBinding: message.stringValue = L10n.tr("recorder.errorBinding")
            case .conflict(let first, let second):
                let other = first == action ? second : first
                message.stringValue = L10n.tr("recorder.errorConflict", ShortcutDisplay.shared.actionName(other))
            }
            return
        }
        Settings.shortcuts = candidate
        stopRecording()
        message.stringValue = L10n.tr("recorder.saved")
    }

    private func stopRecording() {
        guard recordingAction != nil else { return }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        recordingAction = nil
        NotificationCenter.default.post(name: KeyboardController.recordingDidChange, object: false)
        refresh()
    }

    @objc private func clear(_ sender: NSButton) {
        stopRecording()
        // Deleting must also be possible when another stored binding conflicts after a layout change.
        var candidate = Settings.shortcuts
        candidate[ShortcutAction.allCases[sender.tag]] = .disabled
        Settings.shortcuts = candidate
        message.stringValue = L10n.tr("recorder.saved")
    }

    @objc private func reset(_ sender: NSButton) {
        stopRecording()
        let action = ShortcutAction.allCases[sender.tag]
        save(ShortcutSettings()[action], for: action)
    }

    @objc private func resetAll() {
        stopRecording()
        Settings.shortcuts = ShortcutSettings()
        message.stringValue = L10n.tr("recorder.saved")
    }

    func windowWillClose(_ notification: Notification) { stopRecording() }
    func windowDidResignKey(_ notification: Notification) { stopRecording() }
}
