import Foundation

/// Carbon-compatible modifier bits, without an AppKit/Carbon dependency.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 8)
    public static let shift = Self(rawValue: 1 << 9)
    public static let option = Self(rawValue: 1 << 11)
    public static let control = Self(rawValue: 1 << 12)
    public var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { contains($0.0) }.map { $0.1 }.joined()
    }
}

public struct ShortcutChord: Hashable, Sendable {
    public var keyCode: Int
    public var modifiers: ShortcutModifiers
    public init(keyCode: Int, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum ShortcutAction: String, Codable, CaseIterable, Sendable {
    case left, right, up, down, flyout, layouts, workspaces
    // Existing fixed monitor shortcuts are reserved, not new configurable actions.
    case monitorLeft, monitorRight, monitorUp, monitorDown
    public static let configurable: [Self] = [.left, .right, .up, .down, .flyout, .layouts, .workspaces]
    public var isDigitGroup: Bool { self == .layouts || self == .workspaces }
}

public enum ShortcutBinding: Codable, Equatable, Sendable {
    case disabled
    case key(Int, ShortcutModifiers)
    case flyoutDefault(ShortcutModifiers)
    case digits(ShortcutModifiers)

    public var modifiers: ShortcutModifiers {
        switch self {
        case .disabled: return []
        case .key(_, let mods), .flyoutDefault(let mods), .digits(let mods): return mods
        }
    }
}

public enum ShortcutValidationError: Equatable, Sendable {
    case missingModifiers
    case conflict(ShortcutAction)
}

public struct ShortcutSettings: Codable, Equatable, Sendable {
    private var bindings: [ShortcutAction: ShortcutBinding] = [:]
    public static let digitKeys = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    public init() {}

    public subscript(action: ShortcutAction) -> ShortcutBinding {
        get { bindings[action] ?? Self.defaultBinding(for: action) }
        set {
            if newValue == Self.defaultBinding(for: action) { bindings.removeValue(forKey: action) }
            else { bindings[action] = newValue }
        }
    }

    private static func defaultBinding(for action: ShortcutAction) -> ShortcutBinding {
        let mods: ShortcutModifiers = [.control, .option]
        switch action {
        case .left: return .key(123, mods)
        case .right: return .key(124, mods)
        case .up: return .key(126, mods)
        case .down: return .key(125, mods)
        case .flyout: return .flyoutDefault(mods)
        case .layouts: return .digits(mods)
        case .workspaces: return .digits(mods.union(.shift))
        case .monitorLeft: return .key(123, mods.union(.shift))
        case .monitorRight: return .key(124, mods.union(.shift))
        case .monitorUp: return .key(126, mods.union(.shift))
        case .monitorDown: return .key(125, mods.union(.shift))
        }
    }

    public func chords(for action: ShortcutAction, flyoutKey: Int = 6) -> [ShortcutChord] {
        switch self[action] {
        case .disabled: return []
        case .key(let code, let mods): return [.init(keyCode: code, modifiers: mods)]
        case .flyoutDefault(let mods): return [.init(keyCode: flyoutKey, modifiers: mods)]
        case .digits(let mods): return Self.digitKeys.map { .init(keyCode: $0, modifiers: mods) }
        }
    }

    /// Validate all nine keys in a group, including reserved monitor shortcuts.
    public func validationError(for action: ShortcutAction, binding: ShortcutBinding,
                                flyoutKey: Int = 6) -> ShortcutValidationError? {
        if binding == .disabled { return nil }
        guard !binding.modifiers.isEmpty else { return .missingModifiers }
        var candidate = self
        candidate[action] = binding
        let keys = Set(candidate.chords(for: action, flyoutKey: flyoutKey))
        for other in ShortcutAction.allCases where other != action {
            if !keys.isDisjoint(with: chords(for: other, flyoutKey: flyoutKey)) { return .conflict(other) }
        }
        return nil
    }
}
