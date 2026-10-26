import AppKit
import SnaplineCore

@MainActor
final class ShortcutRecorderController: NSWindowController, NSWindowDelegate {
    private let keyboard: KeyboardController
    private let rows = NSStackView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var recording: ShortcutAction?
    private var recordingError = false
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(keyboard: KeyboardController) {
        self.keyboard = keyboard
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 510),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L10n.tr("recorder.title")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        let info = NSTextField(wrappingLabelWithString: L10n.tr("recorder.info"))
        message.textColor = .secondaryLabelColor
        let reset = button(L10n.tr("recorder.resetAll"), #selector(resetAll), tag: 0)
        let stack = NSStackView(views: [info, rows, message, reset])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
                info.widthAnchor.constraint(equalTo: stack.widthAnchor),
                message.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ])
        }
        for name in [Settings.shortcutsDidChange, ShortcutLabels.didChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        reload()
        NSApp.activate()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func button(_ title: String, _ action: Selector, tag: Int) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.tag = tag
        return button
    }

    private func reload() {
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        for (i, action) in ShortcutAction.configurable.enumerated() {
            let title = NSTextField(labelWithString: ShortcutLabels.name(action))
            title.widthAnchor.constraint(equalToConstant: 210).isActive = true
            let value = NSTextField(labelWithString: ShortcutLabels.label(for: action))
            value.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let row = NSStackView(views: [title, value,
                button(L10n.tr("recorder.record"), #selector(record(_:)), tag: i),
                button(L10n.tr("common.delete"), #selector(clear(_:)), tag: i),
                button(L10n.tr("recorder.reset"), #selector(reset(_:)), tag: i)])
            row.spacing = 8
            rows.addArrangedSubview(row)
        }
    }

    @objc private func record(_ sender: NSButton) {
        stopRecording()
        let action = ShortcutAction.configurable[sender.tag]
        recording = action
        recordingError = false
        keyboard.suspend(true)
        message.stringValue = L10n.tr(action.isDigitGroup ? "recorder.pressModifiers" : "recorder.pressKey")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return event }
                return self.capture(event)
            }
        }
    }

    private func capture(_ event: NSEvent) -> NSEvent? {
        guard let action = recording, event.window === window else { return event }
        if event.type == .keyDown, event.keyCode == 53 { stopRecording(); message.stringValue = ""; return nil }
        let modifiers = ShortcutModifiers(flags: event.modifierFlags)
        if event.type == .flagsChanged {
            if action.isDigitGroup && !recordingError {
                message.stringValue = L10n.tr("recorder.confirmModifiers", modifiers.symbols)
            }
            return nil
        }
        // Digit groups accept any key to confirm the held modifiers; their physical digits stay fixed.
        let binding: ShortcutBinding = action.isDigitGroup ? .digits(modifiers) : .key(Int(event.keyCode), modifiers)
        apply(binding, to: action)
        return nil
    }

    private func apply(_ binding: ShortcutBinding, to action: ShortcutAction) {
        var settings = Settings.shortcuts
        if let error = settings.validationError(for: action, binding: binding, flyoutKey: ShortcutLabels.flyoutKey) {
            recordingError = true
            switch error {
            case .missingModifiers: message.stringValue = L10n.tr("recorder.missingModifiers")
            case .conflict(let other): message.stringValue = L10n.tr("recorder.conflict", ShortcutLabels.name(other))
            }
            return
        }
        stopRecording()
        settings[action] = binding
        Settings.shortcuts = settings
        message.stringValue = L10n.tr("recorder.saved")
    }

    @objc private func clear(_ sender: NSButton) { apply(.disabled, to: ShortcutAction.configurable[sender.tag]) }
    @objc private func reset(_ sender: NSButton) {
        let action = ShortcutAction.configurable[sender.tag]
        apply(ShortcutSettings()[action], to: action)
    }
    @objc private func resetAll() {
        stopRecording()
        Settings.shortcuts = ShortcutSettings()
        message.stringValue = L10n.tr("recorder.saved")
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingError = false
        if recording != nil { recording = nil; keyboard.suspend(false) }
    }

    func windowWillClose(_ notification: Notification) { stopRecording() }
    func windowDidResignKey(_ notification: Notification) { stopRecording() }
}
