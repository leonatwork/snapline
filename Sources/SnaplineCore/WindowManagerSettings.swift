/// A freshly read snapshot of com.apple.WindowManager, with macOS' existing
/// tiling defaults. No preferences or AppKit access is needed for the decision.
public struct WindowManagerSettings {
    public let stageManagerEnabled: Bool
    public let edgeDragEnabled: Bool
    public let topEdgeDragEnabled: Bool
    public let optionDragEnabled: Bool

    public init(stageManagerEnabled: Bool? = nil, edgeDragEnabled: Bool? = nil,
                topEdgeDragEnabled: Bool? = nil, optionDragEnabled: Bool? = nil) {
        self.stageManagerEnabled = stageManagerEnabled ?? false
        self.edgeDragEnabled = edgeDragEnabled ?? true
        self.topEdgeDragEnabled = topEdgeDragEnabled ?? true
        self.optionDragEnabled = optionDragEnabled ?? true
    }

    public struct Warnings {
        public let stageManager: Bool
        public let nativeTiling: Bool
    }

    public func warnings(dragSnapEnabled: Bool, zoneDragEnabled: Bool,
                         zoneModifierIsOption: Bool) -> Warnings {
        let conflicts = edgeDragEnabled || topEdgeDragEnabled
            || (optionDragEnabled && zoneModifierIsOption)
        return Warnings(stageManager: stageManagerEnabled,
                        nativeTiling: conflicts && (dragSnapEnabled || zoneDragEnabled))
    }

    /// The confirmation dialog and the writer share this exact allowlist.
    /// GloballyEnabled (Stage Manager) must never be changed by this action.
    public static let tilingKeys = [
        "EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag", "EnableTilingOptionAccelerator",
    ]

    public static func disableTiling(confirmed: Bool, write: (String, Bool) -> Void) {
        guard confirmed else { return }
        for key in tilingKeys { write(key, false) }
    }
}
