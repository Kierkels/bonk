import AppKit
import Carbon.HIToolbox

/// Registreert één systeembrede sneltoets via Carbon `RegisterEventHotKey`.
/// Bewust Carbon en niet een `NSEvent`-global-monitor: Carbon-hotkeys werken
/// zónder Accessibility-toestemming (geen TCC-prompt).
final class HotKeyManager {
    /// Wordt op de main-thread aangeroepen wanneer de sneltoets wordt ingedrukt.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: KeyShortcut?
    private let signature: OSType = 0x424F4E4B // 'BONK'

    /// (Her)registreert de sneltoets. `nil` = geen sneltoets (uitgeschakeld).
    func update(_ shortcut: KeyShortcut?) {
        guard shortcut != current else { return }
        current = shortcut
        unregister()
        guard let shortcut, shortcut.hasRequiredModifier else { return }
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(from: shortcut.modifierFlags),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr { hotKeyRef = ref }
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Zet Cocoa-modifiers om naar Carbon-vlaggen voor `RegisterEventHotKey`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var c: UInt32 = 0
        if flags.contains(.command) { c |= UInt32(cmdKey) }
        if flags.contains(.option)  { c |= UInt32(optionKey) }
        if flags.contains(.control) { c |= UInt32(controlKey) }
        if flags.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
