import Foundation
import Testing
@testable import SnaplineCore

@Suite struct ShortcutTests {
    @Test func defaultsPreserveExistingShortcuts() {
        let settings = ShortcutSettings()
        #expect(settings.chords(for: .left).first == ShortcutChord(keyCode: 123, modifiers: [.control, .option]))
        #expect(settings.chords(for: .right).first == ShortcutChord(keyCode: 124, modifiers: [.control, .option]))
        #expect(settings.chords(for: .up).first == ShortcutChord(keyCode: 126, modifiers: [.control, .option]))
        #expect(settings.chords(for: .down).first == ShortcutChord(keyCode: 125, modifiers: [.control, .option]))
        #expect(settings.chords(for: .layouts).map(\.keyCode) == [18, 19, 20, 21, 23, 22, 26, 28, 25])
        #expect(settings.chords(for: .layouts).allSatisfy { $0.modifiers == [.control, .option] })
        #expect(settings.chords(for: .workspaces).map(\.keyCode) == [18, 19, 20, 21, 23, 22, 26, 28, 25])
        #expect(settings.chords(for: .workspaces).allSatisfy { $0.modifiers == [.control, .option, .shift] })
        #expect(settings.chords(for: .flyout, flyoutKey: 6).first?.keyCode == 6)
        #expect(settings.chords(for: .flyout).first?.modifiers == [.control, .option])
        #expect(settings.chords(for: .flyout, flyoutKey: 16).first?.keyCode == 16)
        #expect(settings.chords(for: .flyout, flyoutKey: 13).first?.keyCode == 13)
    }

    @Test func roundTripPreservesDisabledAndPhysicalKeys() throws {
        var settings = ShortcutSettings()
        settings[.left] = .key(0, [.command, .shift])
        settings[.flyout] = .key(6, [.option])
        settings[.layouts] = .disabled
        let restored = try JSONDecoder().decode(ShortcutSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored == settings)
        #expect(restored.chords(for: .layouts).isEmpty)
        #expect(restored.chords(for: .flyout, flyoutKey: 13).first?.keyCode == 6)
        #expect(restored.chords(for: .left).first?.keyCode == 0)
    }

    @Test func duplicateAndModifierlessAssignmentsAreRejected() {
        let settings = ShortcutSettings()
        #expect(settings.validationError(for: .right, binding: settings[.left]) == .conflict(.left))
        #expect(settings.validationError(for: .left, binding: .key(0, [])) == .missingModifiers)
        #expect(settings.validationError(for: .layouts, binding: .digits([])) == .missingModifiers)
        #expect(settings.validationError(for: .left, binding: settings[.left]) == nil)
        #expect(settings.validationError(for: .left, binding: .disabled) == nil)
    }

    @Test func groupsAndReservedMonitorKeysParticipateInConflicts() {
        let settings = ShortcutSettings()
        #expect(settings.validationError(for: .workspaces, binding: .digits([.control, .option])) == .conflict(.layouts))
        #expect(settings.validationError(for: .left, binding: .key(18, [.control, .option])) == .conflict(.layouts))
        #expect(settings.validationError(for: .left, binding: .key(123, [.control, .option, .shift])) == .conflict(.monitorLeft))
        #expect(settings.validationError(for: .left, binding: .key(13, [.control, .option]), flyoutKey: 13) == .conflict(.flyout))
    }

    @Test func deletingFreesShortcutAndResetRestoresDefaults() {
        var settings = ShortcutSettings()
        settings[.left] = .disabled
        #expect(settings.chords(for: .left).isEmpty)
        #expect(settings.validationError(for: .right, binding: .key(123, [.control, .option])) == nil)
        settings[.left] = ShortcutSettings()[.left]
        #expect(settings == ShortcutSettings())
    }

    @Test func modifierSymbolsHaveStableMacOrder() {
        #expect(ShortcutModifiers().symbols == "")
        #expect(ShortcutModifiers.control.symbols == "⌃")
        #expect(ShortcutModifiers.option.symbols == "⌥")
        #expect(ShortcutModifiers.shift.symbols == "⇧")
        #expect(ShortcutModifiers.command.symbols == "⌘")
        #expect(ShortcutModifiers([.command, .shift, .option, .control]).symbols == "⌃⌥⇧⌘")
    }
}
