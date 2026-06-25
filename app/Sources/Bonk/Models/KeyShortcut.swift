import AppKit

/// Een door de gebruiker instelbare toetscombinatie voor een globale sneltoets.
/// Bewaart de virtuele keyCode + Cocoa-modifiers en een display-token zodat we
/// het label kunnen tonen zonder keyCode→teken-vertaling.
struct KeyShortcut: Codable, Equatable {
    var keyCode: Int        // NSEvent.keyCode (hardware-onafhankelijke virtuele toets)
    var modifiers: UInt     // NSEvent.ModifierFlags.rawValue (device-independent subset)
    var key: String         // display-token, bv. "R", "Space", "↩"

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
    }

    /// Minstens één van ⌘/⌃/⌥ vereist — anders zou de sneltoets normaal typen kapen.
    var hasRequiredModifier: Bool {
        let f = modifierFlags
        return f.contains(.command) || f.contains(.control) || f.contains(.option)
    }

    /// Leesbaar label in standaard macOS-volgorde: ⌃⌥⇧⌘ + toets.
    var displayString: String {
        let f = modifierFlags
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s + key
    }

    /// Bouwt een shortcut uit een opgevangen `NSEvent` (keyDown). Geeft nil als er
    /// geen geldige modifier bij zit.
    static func from(event: NSEvent) -> KeyShortcut? {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let token = displayToken(for: event)
        let shortcut = KeyShortcut(keyCode: Int(event.keyCode), modifiers: mods.rawValue, key: token)
        return shortcut.hasRequiredModifier ? shortcut : nil
    }

    /// Display-token voor een toets: het zichtbare teken (hoofdletter) of een
    /// symbool/naam voor speciale toetsen.
    static func displayToken(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let chars = (event.charactersIgnoringModifiers ?? "").uppercased()
        // Filter control-tekens; val terug op de keyCode als er niets bruikbaars is.
        if let c = chars.unicodeScalars.first, c.value >= 0x20, c.value != 0x7F {
            return chars
        }
        return "⌥\(event.keyCode)" // onwaarschijnlijke fallback
    }

    /// Veelvoorkomende speciale toetsen (kVK_* virtuele keyCodes).
    static let specialKeys: [Int: String] = [
        0x24: "↩",   // Return
        0x4C: "⌅",   // Keypad Enter
        0x30: "⇥",   // Tab
        0x31: "Space",
        0x33: "⌫",   // Delete (backspace)
        0x75: "⌦",   // Forward delete
        0x35: "⎋",   // Escape
        0x7B: "←", 0x7C: "→", 0x7E: "↑", 0x7D: "↓",
        0x73: "↖", 0x77: "↘", 0x74: "⇞", 0x79: "⇟",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
        0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
    ]
}
