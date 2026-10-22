import AppKit
import Carbon.HIToolbox
import SnaplineCore

extension ShortcutModifiers {
    init(flags: NSEvent.ModifierFlags) {
        self.init()
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }

    var carbon: Int {
        (contains(.control) ? controlKey : 0) | (contains(.option) ? optionKey : 0)
            | (contains(.shift) ? shiftKey : 0) | (contains(.command) ? cmdKey : 0)
    }
}

/// One source for registration and labels. UCKeyTranslate deliberately ignores modifiers:
/// the label is the physical key's base legend, even on AZERTY's number row.
@MainActor
final class ShortcutDisplay: NSObject {
    static let shared = ShortcutDisplay()
    static let inputSourceDidChange = Notification.Name("Snapline.shortcutInputSourceDidChange")
    private var cachedFlyoutKey: UInt16?

    private override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(inputSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil)
    }

    @objc private func inputSourceChanged() {
        cachedFlyoutKey = nil
        NotificationCenter.default.post(name: Self.inputSourceDidChange, object: nil)
    }

    func keyLabel(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        default: break
        }
        if let text = translatedKey(code), !text.isEmpty,
           text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return text.uppercased()
        }
        let functionKeys = [122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6,
                            98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
                            105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20]
        if let number = functionKeys[Int(code)] { return "F\(number)" }
        return L10n.tr("recorder.keyCode", Int(code))
    }

    private func translatedKey(_ code: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKey: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                    &deadKey, characters.count, &length, &characters)
        guard status == noErr else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    var defaultFlyoutKey: UInt16 {
        if let cachedFlyoutKey { return cachedFlyoutKey }
        let code = (UInt16(0)..<128).first { translatedKey($0)?.lowercased() == "z" } ?? UInt16(kVK_ANSI_Z)
        cachedFlyoutKey = code
        return code
    }

    func shortcuts(for action: ShortcutAction) -> [Shortcut] {
        Settings.shortcuts.shortcuts(for: action, defaultFlyoutKey: defaultFlyoutKey)
    }

    func label(_ shortcut: Shortcut) -> String {
        shortcut.modifiers.symbols + keyLabel(shortcut.keyCode)
    }

    func label(for action: ShortcutAction, index: Int? = nil) -> String {
        let keys = shortcuts(for: action)
        if let index { return keys.indices.contains(index) ? label(keys[index]) : "" }
        guard let first = keys.first else { return L10n.tr("recorder.disabled") }
        if action.isDigitGroup, let last = keys.last {
            return first.modifiers.symbols + keyLabel(first.keyCode) + "…" + keyLabel(last.keyCode)
        }
        return label(first)
    }

    func actionName(_ action: ShortcutAction) -> String {
        switch action {
        case .left: return L10n.tr("recorder.left")
        case .right: return L10n.tr("recorder.right")
        case .up: return L10n.tr("recorder.up")
        case .down: return L10n.tr("recorder.down")
        case .flyout: return L10n.tr("recorder.flyout")
        case .layouts: return L10n.tr("recorder.layouts")
        case .workspaces: return L10n.tr("recorder.workspaces")
        }
    }
}
