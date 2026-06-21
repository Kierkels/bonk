import XCTest
@testable import Bonk

final class MeetingRuleTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyRuleMatchesEverything() {
        let e = makeEvent(start: start)
        XCTAssertTrue(makeRule().matches(e))
    }

    func testDisabledRuleNeverMatches() {
        let e = makeEvent(start: start)
        XCTAssertFalse(makeRule(isEnabled: false).matches(e))
    }

    func testTitleContainsIsCaseInsensitive() {
        let e = makeEvent(title: "Sprint Review", start: start)
        XCTAssertTrue(makeRule(titleContains: "review").matches(e))
        XCTAssertFalse(makeRule(titleContains: "standup").matches(e))
    }

    func testOnlyAcceptedFiltersUnaccepted() {
        let accepted = makeEvent(start: start, isAccepted: true)
        let declined = makeEvent(start: start, isAccepted: false)
        XCTAssertTrue(makeRule(onlyAccepted: true).matches(accepted))
        XCTAssertFalse(makeRule(onlyAccepted: true).matches(declined))
    }

    func testCalendarIDScoping() {
        let e = makeEvent(start: start, calendarID: "work")
        XCTAssertTrue(makeRule(calendarID: "work").matches(e))
        XCTAssertFalse(makeRule(calendarID: "home").matches(e))
    }

    func testCalendarScopedRuleDoesNotMatchReminder() {
        // Herinneringen hebben calendarID "bonk.reminder" → een agenda-gebonden
        // regel mag er niet op passen.
        let reminder = makeEvent(id: "reminder:1", start: start, calendarID: "bonk.reminder")
        XCTAssertFalse(makeRule(calendarID: "work").matches(reminder))
    }

    func testDaysOfWeekFilter() {
        // weekday 2 = maandag (Calendar-conventie)
        let e = makeEvent(start: start, weekday: 2)
        XCTAssertTrue(makeRule(daysOfWeek: [2, 3, 4, 5, 6]).matches(e))
        XCTAssertFalse(makeRule(daysOfWeek: [7, 1]).matches(e))   // weekend
    }
}

final class UpdateCheckerVersionTests: XCTestCase {

    func testNewerVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))    // numeriek, niet lexicaal
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
    }

    func testNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9", than: "1.10"))
    }
}
