import XCTest
import SwiftUI
@testable import Bonk

final class ColorHelperTests: XCTestCase {

    func testHexRoundTrip() {
        XCTAssertEqual(Color(hex: "#E72677").hexString, "#E72677")
        XCTAssertEqual(Color(hex: "7C3AED").hexString, "#7C3AED")
    }

    func testReadableForegroundContrast() {
        // Donkere achtergrond → witte tekst; lichte achtergrond → zwarte tekst.
        XCTAssertEqual(Color(hex: "#7C3AED").readableForeground, Color.white)   // paars (donker)
        XCTAssertEqual(Color(hex: "#FFFFFF").readableForeground, Color.black)   // wit
        XCTAssertEqual(Color(hex: "#000000").readableForeground, Color.white)   // zwart
    }
}

final class CleanNotesTests: XCTestCase {

    func testStripsGoogleBoilerplate() {
        let raw = "Bespreek de planning.\n-::~:~::~:~::~:~::~:~::~:~::~:~::~:~::~:~::~:~::~:~::~::~\nJoin Google Meet\nmeet.google.com/abc"
        XCTAssertEqual(CalendarManager.cleanNotes(raw), "Bespreek de planning.")
    }

    func testStripsHTMLAndEntities() {
        XCTAssertEqual(CalendarManager.cleanNotes("<b>Hoi</b> &amp; tot zo"), "Hoi & tot zo")
    }

    func testEmptyBecomesNil() {
        XCTAssertNil(CalendarManager.cleanNotes("   \n  "))
        XCTAssertNil(CalendarManager.cleanNotes(nil))
    }
}
