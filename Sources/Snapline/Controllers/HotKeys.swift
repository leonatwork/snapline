import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon – no Accessibility permission required.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private var installed = false
    private var eventHandler: EventHandlerRef?

    private static let signature: OSType = 0x534E_504C  // 'SNPL'

    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> OSStatus {
        let installationStatus = installHandlerIfNeeded()
        guard installationStatus == noErr else { return installationStatus }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Snapline: could not register hotkey \(keyCode) (\(status))")
            return status == noErr ? OSStatus(paramErr) : status
        }
        refs.append(ref)
        handlers[id] = handler
        return noErr
    }

    /// Clear callbacks before unregistering, so queued events cannot invoke old actions.
    @discardableResult
    func unregisterAll() -> OSStatus {
        handlers.removeAll()
        var failed: [EventHotKeyRef] = []
        var result: OSStatus = noErr
        for ref in refs {
            let status = UnregisterEventHotKey(ref)
            if status != noErr { failed.append(ref); result = status }
        }
        refs = failed
        return result
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() -> OSStatus {
        guard !installed else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == HotKeyCenter.signature else { return status }
            MainActor.assumeIsolated { HotKeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        installed = status == noErr
        return status
    }
}
