import Testing
@testable import SnaplineCore

@Suite struct WindowManagerSettingsTests {
    // nil exercises absent keys as well as every explicit on/off combination.
    @Test func warningMatrix() {
        let values: [Bool?] = [nil, false, true]
        for stage in values {
            for edge in values {
                for top in values {
                    for option in values {
                        for optionModifier in [false, true] { // ⌘ versus ⌥
                            for dragSnap in [false, true] {
                                for zoneDrag in [false, true] {
                                    let settings = WindowManagerSettings(
                                        stageManagerEnabled: stage, edgeDragEnabled: edge,
                                        topEdgeDragEnabled: top, optionDragEnabled: option)
                                    let warnings = settings.warnings(
                                        dragSnapEnabled: dragSnap, zoneDragEnabled: zoneDrag,
                                        zoneModifierIsOption: optionModifier)
                                    #expect(warnings.stageManager == (stage == true))
                                    let conflicts = edge != false || top != false
                                        || (option != false && optionModifier)
                                    #expect(warnings.nativeTiling == (conflicts && (dragSnap || zoneDrag)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func missingKeysPreserveExistingDefaults() {
        let settings = WindowManagerSettings()
        #expect(!settings.stageManagerEnabled)
        #expect(settings.edgeDragEnabled)
        #expect(settings.topEdgeDragEnabled)
        #expect(settings.optionDragEnabled)
    }

    @Test func newSnapshotReflectsStageManagerToggleWithoutDragSnap() {
        for stage in [false, true, false] {
            let warnings = WindowManagerSettings(stageManagerEnabled: stage).warnings(
                dragSnapEnabled: false, zoneDragEnabled: false, zoneModifierIsOption: false)
            #expect(warnings.stageManager == stage)
            #expect(!warnings.nativeTiling)
        }
    }

    @Test func cancellingDoesNotWriteAnySettings() {
        var writes: [String: Bool] = [:]
        WindowManagerSettings.disableTiling(confirmed: false) { writes[$0] = $1 }
        #expect(writes.isEmpty)
    }

    @Test func confirmationWritesExactlyTheListedTilingKeys() {
        var values = ["GloballyEnabled": true, "unrelated": true]
        var writtenKeys: [String] = []
        WindowManagerSettings.disableTiling(confirmed: true) { key, value in
            writtenKeys.append(key)
            values[key] = value
        }
        let expected = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag", "EnableTilingOptionAccelerator"]
        #expect(WindowManagerSettings.tilingKeys == expected)
        #expect(writtenKeys == expected)
        #expect(expected.allSatisfy { values[$0] == false })
        #expect(values["GloballyEnabled"] == true)
        #expect(values["unrelated"] == true)
        let warnings = WindowManagerSettings(
            stageManagerEnabled: values["GloballyEnabled"],
            edgeDragEnabled: values[expected[0]], topEdgeDragEnabled: values[expected[1]],
            optionDragEnabled: values[expected[2]]).warnings(
                dragSnapEnabled: true, zoneDragEnabled: true, zoneModifierIsOption: true)
        #expect(!warnings.nativeTiling)
        #expect(warnings.stageManager) // Disabling Stage Manager is out of scope.
    }
}
