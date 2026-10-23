import Foundation

/// Independent of AppKit and Carbon; only the four recordable modifiers are stored.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
    public static let all: Self = [.control, .option, .shift, .command]

    public var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}

public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down, flyout, layouts, workspaces
    public var isDigitGroup: Bool { self == .layouts || self == .workspaces }
}

public enum ShortcutBinding: Codable, Equatable, Sendable {
    case disabled
    case key(Shortcut)
    case digits(ShortcutModifiers)
    /// Only the default flyout follows the input source; recorded keys remain physical.
    case defaultFlyout
}

public enum ShortcutValidationError: Equatable, Sendable {
    case missingModifiers(ShortcutAction)
    case conflict(ShortcutAction, ShortcutAction)
    case invalidBinding(ShortcutAction)
}

public struct ShortcutSettings: Codable, Equatable, Sendable {
    private var bindings: [ShortcutAction: ShortcutBinding] = [:]
    public init() {}

    public subscript(action: ShortcutAction) -> ShortcutBinding {
        get { bindings[action] ?? Self.defaultBinding(for: action) }
        set {
            // Keep reset-to-default settings identical to a fresh installation.
            bindings[action] = newValue == Self.defaultBinding(for: action) ? nil : newValue
        }
    }

    private static func defaultBinding(for action: ShortcutAction) -> ShortcutBinding {
        let modifiers: ShortcutModifiers = [.control, .option]
        switch action {
        case .left: return .key(Shortcut(keyCode: 123, modifiers: modifiers))
        case .right: return .key(Shortcut(keyCode: 124, modifiers: modifiers))
        case .up: return .key(Shortcut(keyCode: 126, modifiers: modifiers))
        case .down: return .key(Shortcut(keyCode: 125, modifiers: modifiers))
        case .flyout: return .defaultFlyout
        case .layouts: return .digits(modifiers)
        case .workspaces: return .digits([.control, .option, .shift])
        }
    }

    /// Physical positions of 1…9, including the nonsequential Carbon key codes.
    public static let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    public func shortcuts(for action: ShortcutAction, defaultFlyoutKey: UInt16 = 6) -> [Shortcut] {
        switch self[action] {
        case .disabled: return []
        case .key(let shortcut): return [shortcut]
        case .digits(let modifiers): return Self.digitKeys.map { Shortcut(keyCode: $0, modifiers: modifiers) }
        case .defaultFlyout: return [Shortcut(keyCode: defaultFlyoutKey, modifiers: [.control, .option])]
        }
    }

    public func validationError(defaultFlyoutKey: UInt16) -> ShortcutValidationError? {
        var used: [Shortcut: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            switch self[action] {
            case .disabled: continue
            case .key where action.isDigitGroup: return .invalidBinding(action)
            case .digits where !action.isDigitGroup: return .invalidBinding(action)
            case .defaultFlyout where action != .flyout: return .invalidBinding(action)
            default: break
            }
            for shortcut in shortcuts(for: action, defaultFlyoutKey: defaultFlyoutKey) {
                guard !shortcut.modifiers.isEmpty, shortcut.modifiers.subtracting(.all).isEmpty else {
                    return .missingModifiers(action)
                }
                guard shortcut.keyCode < 128 else { return .invalidBinding(action) }
                if let other = used[shortcut] { return .conflict(other, action) }
                used[shortcut] = action
            }
        }
        return nil
    }
}
