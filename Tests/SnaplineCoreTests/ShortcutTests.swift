import Foundation
import Testing
@testable import SnaplineCore

@Suite struct ShortcutTests {
    @Test func defaultsPreserveExistingShortcuts() {
        let settings = ShortcutSettings()
        #expect(settings.shortcuts(for: .left) == [Shortcut(keyCode: 123, modifiers: [.control, .option])])
        #expect(settings.shortcuts(for: .right).first?.keyCode == 124)
        #expect(settings.shortcuts(for: .up).first?.keyCode == 126)
        #expect(settings.shortcuts(for: .down).first?.keyCode == 125)
        #expect(settings.shortcuts(for: .flyout).first?.keyCode == 6)
        #expect(settings.shortcuts(for: .layouts).map(\.keyCode) == [18, 19, 20, 21, 23, 22, 26, 28, 25])
        #expect(settings.shortcuts(for: .workspaces).allSatisfy { $0.modifiers == [.control, .option, .shift] })
        #expect(settings.validationError(defaultFlyoutKey: 6) == nil)
    }

    @Test func roundTripPreservesDisabledAndPhysicalBindings() throws {
        var settings = ShortcutSettings()
        settings[.left] = .key(Shortcut(keyCode: 0, modifiers: [.command, .shift]))
        settings[.right] = .disabled
        settings[.layouts] = .digits([.command])
        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(ShortcutSettings.self, from: data)
        #expect(restored == settings)
        #expect(restored.shortcuts(for: .right).isEmpty)
        #expect(restored.shortcuts(for: .left, defaultFlyoutKey: 13).first?.keyCode == 0)
    }

    @Test func rejectsDuplicatesIncludingEveryDigitInAGroup() {
        var settings = ShortcutSettings()
        settings[.left] = settings[.right]
        #expect(settings.validationError(defaultFlyoutKey: 6) == .conflict(.left, .right))
        settings = ShortcutSettings()
        settings[.left] = .key(Shortcut(keyCode: 25, modifiers: [.control, .option]))
        #expect(settings.validationError(defaultFlyoutKey: 6) == .conflict(.left, .layouts))
        settings = ShortcutSettings()
        settings[.workspaces] = settings[.layouts]
        #expect(settings.validationError(defaultFlyoutKey: 6) == .conflict(.layouts, .workspaces))
    }

    @Test func rejectsMissingAndUnsupportedModifiers() {
        var settings = ShortcutSettings()
        settings[.left] = .key(Shortcut(keyCode: 0, modifiers: []))
        #expect(settings.validationError(defaultFlyoutKey: 6) == .missingModifiers(.left))
        settings[.left] = .key(Shortcut(keyCode: 0, modifiers: ShortcutModifiers(rawValue: 16)))
        #expect(settings.validationError(defaultFlyoutKey: 6) == .missingModifiers(.left))
        settings[.left] = .disabled
        settings[.layouts] = .digits([])
        #expect(settings.validationError(defaultFlyoutKey: 6) == .missingModifiers(.layouts))
    }

    @Test func disabledBindingsDoNotConflictAndResetRestoresDefaults() {
        var settings = ShortcutSettings()
        settings[.left] = .disabled
        #expect(settings.validationError(defaultFlyoutKey: 6) == nil)
        settings[.left] = ShortcutSettings()[.left]
        #expect(settings == ShortcutSettings())
    }

    @Test func defaultFlyoutFollowsLayoutButRecordedKeyDoesNot() {
        var settings = ShortcutSettings()
        #expect(settings.shortcuts(for: .flyout, defaultFlyoutKey: 13).first?.keyCode == 13)
        #expect(settings.shortcuts(for: .flyout, defaultFlyoutKey: 16).first?.keyCode == 16)
        settings[.flyout] = .key(Shortcut(keyCode: 6, modifiers: [.control, .option]))
        #expect(settings.shortcuts(for: .flyout, defaultFlyoutKey: 13).first?.keyCode == 6)
        settings[.layouts] = .key(Shortcut(keyCode: 0, modifiers: [.command]))
        #expect(settings.validationError(defaultFlyoutKey: 13) == .invalidBinding(.layouts))
    }

    @Test func modifierSymbolsHaveStableOrder() {
        #expect(ShortcutModifiers.control.symbols == "⌃")
        #expect(ShortcutModifiers.option.symbols == "⌥")
        #expect(ShortcutModifiers.shift.symbols == "⇧")
        #expect(ShortcutModifiers.command.symbols == "⌘")
        #expect(ShortcutModifiers.all.symbols == "⌃⌥⇧⌘")
        #expect(ShortcutModifiers().symbols.isEmpty)
    }
}
