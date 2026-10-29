import AppKit
import Carbon.HIToolbox
import SnaplineCore

@MainActor
enum ShortcutLabels {
    static let didChange = Notification.Name("Snapline.keyboardLayoutDidChange")
    private static var observer: KeyboardLayoutObserver?

    @MainActor
    private final class KeyboardLayoutObserver: NSObject {
        @objc func inputSourceChanged(_ notification: Notification) {
            NotificationCenter.default.post(name: ShortcutLabels.didChange, object: nil)
        }
    }

    static func start() {
        guard observer == nil else { return }
        let layoutObserver = KeyboardLayoutObserver()
        // Menu-bar apps are usually inactive. The block API defaults to coalescing
        // until activation, leaving the flyout registered on the previous layout.
        // Distributed notifications deliver selectors on the main thread.
        DistributedNotificationCenter.default().addObserver(
            layoutObserver, selector: #selector(KeyboardLayoutObserver.inputSourceChanged(_:)),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
        observer = layoutObserver
    }

    private static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(property, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = buffer.withUnsafeMutableBufferPointer {
            UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKey, $0.count, &length, $0.baseAddress!)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }

    static var flyoutKey: Int {
        (0..<128).first { character(for: $0)?.lowercased() == "z" } ?? kVK_ANSI_Z
    }

    static func key(_ code: Int) -> String {
        switch code {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Space: return "␣"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_KeypadEnter: return "⌤"
        default:
            let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
                                kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            if let i = functionKeys.firstIndex(of: code) { return "F\(i + 1)" }
            if let text = character(for: code),
               !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                return text.uppercased()
            }
            return "#\(code)"
        }
    }

    static func chord(_ chord: ShortcutChord) -> String { chord.modifiers.symbols + key(chord.keyCode) }

    static func chords(for action: ShortcutAction) -> [ShortcutChord] {
        Settings.shortcuts.chords(for: action, flyoutKey: flyoutKey)
    }

    static func label(for action: ShortcutAction) -> String {
        let keys = chords(for: action)
        guard let first = keys.first else { return L10n.tr("recorder.disabled") }
        if action.isDigitGroup, let last = keys.last {
            return first.modifiers.symbols + key(first.keyCode) + "…" + key(last.keyCode)
        }
        return chord(first)
    }

    static func layout(_ number: Int) -> String {
        let keys = chords(for: .layouts)
        guard number > 0, number <= keys.count else { return "" }
        return chord(keys[number - 1])
    }

    static func name(_ action: ShortcutAction) -> String {
        switch action {
        case .left: return L10n.tr("recorder.left")
        case .right: return L10n.tr("recorder.right")
        case .up: return L10n.tr("recorder.up")
        case .down: return L10n.tr("recorder.down")
        case .flyout: return L10n.tr("recorder.flyout")
        case .layouts: return L10n.tr("recorder.layouts")
        case .workspaces: return L10n.tr("recorder.workspaces")
        case .monitorLeft, .monitorRight, .monitorUp, .monitorDown: return L10n.tr("recorder.monitor")
        }
    }

    /// Display-only: global Carbon registration remains the sole shortcut dispatcher.
    /// This also avoids AppKit interpreting AZERTY digit labels as other physical keys.
    static func annotate(_ item: NSMenuItem, chord: ShortcutChord?) {
        if let chord { item.title += "    " + self.chord(chord) }
    }
}

extension ShortcutModifiers {
    init(flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
