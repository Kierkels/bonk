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

    func testAttendanceFilter() {
        let accepted = makeEvent(start: start, attendance: .accepted)
        let invited = makeEvent(start: start, attendance: .invited)
        let info = makeEvent(start: start, attendance: .informational)

        // Filter op {accepted}: alleen geaccepteerd matcht.
        XCTAssertTrue(makeRule(attendanceFilter: [.accepted]).matches(accepted))
        XCTAssertFalse(makeRule(attendanceFilter: [.accepted]).matches(invited))
        XCTAssertFalse(makeRule(attendanceFilter: [.accepted]).matches(info))

        // Filter op {accepted, invited}: beide matchen, info niet.
        let rule = makeRule(attendanceFilter: [.accepted, .invited])
        XCTAssertTrue(rule.matches(accepted))
        XCTAssertTrue(rule.matches(invited))
        XCTAssertFalse(rule.matches(info))

        // Lege filter = alle statussen.
        XCTAssertTrue(makeRule(attendanceFilter: []).matches(info))
    }

    func testCalendarIDScoping() {
        let e = makeEvent(start: start, calendarID: "work")
        XCTAssertTrue(makeRule(calendarID: "work").matches(e))
        XCTAssertFalse(makeRule(calendarID: "home").matches(e))
    }

    func testMultipleCalendarsScoping() {
        var rule = makeRule()
        rule.calendarIDs = ["work", "home"]
        XCTAssertTrue(rule.matches(makeEvent(start: start, calendarID: "work")))
        XCTAssertTrue(rule.matches(makeEvent(start: start, calendarID: "home")))
        XCTAssertFalse(rule.matches(makeEvent(start: start, calendarID: "other")))
        // Lege set = alle agenda's.
        rule.calendarIDs = []
        XCTAssertTrue(rule.matches(makeEvent(start: start, calendarID: "anything")))
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
