import XCTest
import SwiftUI
import EventKit
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

final class CalendarItemURLTests: XCTestCase {

    func testPrefersHTTPSWebLink() {
        let ev = EKEvent(eventStore: EKEventStore())
        ev.url = URL(string: "https://www.google.com/calendar/event?eid=abc123")
        XCTAssertEqual(CalendarManager.calendarItemURL(ev)?.absoluteString,
                       "https://www.google.com/calendar/event?eid=abc123")
    }

    func testIgnoresNonHTTPURLAndFallsBack() {
        // Een niet-http(s) URL telt niet als web-link; zonder opgeslagen
        // eventIdentifier (in-memory event) is er geen ical-fallback → nil.
        let ev = EKEvent(eventStore: EKEventStore())
        ev.url = URL(string: "message://someid")
        XCTAssertNil(CalendarManager.calendarItemURL(ev))
    }

    func testNilWhenNoLink() {
        let ev = EKEvent(eventStore: EKEventStore())
        XCTAssertNil(CalendarManager.calendarItemURL(ev))
    }
}
