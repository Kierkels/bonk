import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Bonk

final class KeyShortcutTests: XCTestCase {

    private func make(_ flags: NSEvent.ModifierFlags, key: String = "R", keyCode: Int = 15) -> KeyShortcut {
        KeyShortcut(keyCode: keyCode, modifiers: flags.rawValue, key: key)
    }

    func testDisplayStringOrder() {
        // Standaard macOS-volgorde: ⌃⌥⇧⌘ + toets.
        XCTAssertEqual(make([.command]).displayString, "⌘R")
        XCTAssertEqual(make([.command, .shift]).displayString, "⇧⌘R")
        XCTAssertEqual(make([.control, .option, .shift, .command]).displayString, "⌃⌥⇧⌘R")
        XCTAssertEqual(make([.command], key: "Space").displayString, "⌘Space")
    }

    func testRequiredModifier() {
        XCTAssertTrue(make([.command]).hasRequiredModifier)
        XCTAssertTrue(make([.control]).hasRequiredModifier)
        XCTAssertTrue(make([.option]).hasRequiredModifier)
        XCTAssertFalse(make([.shift]).hasRequiredModifier)   // shift alleen telt niet
        XCTAssertFalse(make([]).hasRequiredModifier)
    }

    func testCarbonModifierConversion() {
        XCTAssertEqual(HotKeyManager.carbonModifiers(from: [.command]), UInt32(cmdKey))
        XCTAssertEqual(HotKeyManager.carbonModifiers(from: [.command, .shift]),
                       UInt32(cmdKey) | UInt32(shiftKey))
        XCTAssertEqual(HotKeyManager.carbonModifiers(from: [.control, .option]),
                       UInt32(controlKey) | UInt32(optionKey))
    }

    func testFromEventCapturesValidCombo() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15
        ) else { return } // synthetische events kunnen op sommige hosts nil zijn
        let s = KeyShortcut.from(event: event)
        XCTAssertEqual(s?.keyCode, 15)
        XCTAssertEqual(s?.key, "R")
        XCTAssertEqual(s?.displayString, "⇧⌘R")
    }

    func testFromEventRejectsModifierlessKey() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15
        ) else { return }
        XCTAssertNil(KeyShortcut.from(event: event))   // geen ⌘/⌥/⌃ → niet toegestaan
    }
}
