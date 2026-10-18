import Carbon
import GlimpseCore

enum HotkeySlot: UInt32, CaseIterable {
    case capture = 1
    case quit
    case escape
    case confirm
    case confirmKeypad
}

enum KeyCode {
    static let escape: UInt32 = 53
    static let returnKey: UInt32 = 36
    static let keypadEnter: UInt32 = 76
}

/// System-wide shortcuts via Carbon. A registered key is consumed, so the
/// frontmost app never receives it — that's what lets Return paste without also
/// typing a newline.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private static let signature: OSType = 0x474C_4D50 // "GLMP"

    private var refs: [HotkeySlot: EventHotKeyRef] = [:]
    private var handlers: [HotkeySlot: () -> Void] = [:]

    private init() {
        installEventHandler()
    }

    @discardableResult
    func register(_ slot: HotkeySlot, hotkey: Hotkey, handler: @escaping () -> Void) -> Bool {
        register(slot, keyCode: hotkey.keyCode, modifiers: hotkey.modifiers, handler: handler)
    }

    @discardableResult
    func register(_ slot: HotkeySlot, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        unregister(slot)
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[slot] = ref
        handlers[slot] = handler
        return true
    }

    func unregister(_ slot: HotkeySlot) {
        if let ref = refs.removeValue(forKey: slot) {
            UnregisterEventHotKey(ref)
        }
        handlers[slot] = nil
    }

    func isRegistered(_ slot: HotkeySlot) -> Bool {
        refs[slot] != nil
    }

    fileprivate func handle(id: UInt32) {
        guard let slot = HotkeySlot(rawValue: id) else { return }
        handlers[slot]?()
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            // Application-target Carbon events are delivered on the main thread.
            MainActor.assumeIsolated { HotkeyManager.shared.handle(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
