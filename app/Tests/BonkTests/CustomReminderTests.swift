import XCTest
@testable import Bonk

final class CustomReminderTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return c
    }

    /// Bouwt een datum in de test-kalender (Europe/Amsterdam).
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: Eenmalig

    func testOneOffReturnsDateWhenFuture() {
        let when = date(2026, 6, 23, 13, 0)
        let r = CustomReminder(title: "x", date: when)
        XCTAssertEqual(r.nextOccurrence(onOrAfter: date(2026, 6, 23, 9, 0), calendar: cal), when)
    }

    func testOneOffReturnsNilWhenPast() {
        let when = date(2026, 6, 23, 13, 0)
        let r = CustomReminder(title: "x", date: when)
        XCTAssertNil(r.nextOccurrence(onOrAfter: date(2026, 6, 23, 14, 0), calendar: cal))
    }

    // MARK: Elke dag

    func testDailyKeepsTodayIfTimeNotPassed() {
        let r = CustomReminder(title: "x", date: date(2026, 6, 23, 13, 0), repeatRule: .daily)
        // Om 09:00 is 13:00 vandaag nog het eerstvolgende moment.
        XCTAssertEqual(r.nextOccurrence(onOrAfter: date(2026, 6, 23, 9, 0), calendar: cal),
                       date(2026, 6, 23, 13, 0))
    }

    func testDailyRollsToTomorrowAfterTime() {
        let r = CustomReminder(title: "x", date: date(2026, 6, 23, 13, 0), repeatRule: .daily)
        // Net na 13:00 → morgen 13:00 (tijdstip blijft behouden).
        XCTAssertEqual(r.nextOccurrence(onOrAfter: date(2026, 6, 23, 13, 0, 1), calendar: cal),
                       date(2026, 6, 24, 13, 0))
    }

    // MARK: Werkdagen (ma–vr)

    func testWeekdaysSkipsWeekend() {
        // 26 juni 2026 is een vrijdag; na vrijdag 13:00 → maandag 29 juni.
        let r = CustomReminder(title: "x", date: date(2026, 6, 26, 13, 0), repeatRule: .weekdays)
        let next = r.nextOccurrence(onOrAfter: date(2026, 6, 26, 13, 0, 1), calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 29, 13, 0))
        XCTAssertEqual(cal.component(.weekday, from: next!), 2) // maandag
    }

    // MARK: Wekelijks

    func testWeeklyPicksNextSelectedDay() {
        // Alleen woensdag (weekday 4). Vanaf maandag 22 juni → woensdag 24 juni.
        let r = CustomReminder(title: "x", date: date(2026, 6, 24, 13, 0),
                               repeatRule: .weekly, weekdays: [4])
        let next = r.nextOccurrence(onOrAfter: date(2026, 6, 22, 9, 0), calendar: cal)
        XCTAssertEqual(next, date(2026, 6, 24, 13, 0))
    }

    func testWeeklyEmptyFallsBackToDateWeekday() {
        // Geen dagen gekozen → val terug op de weekdag van de ingestelde datum (wo 24 juni).
        let r = CustomReminder(title: "x", date: date(2026, 6, 24, 13, 0), repeatRule: .weekly)
        XCTAssertEqual(r.activeWeekdays(calendar: cal), [4])
    }

    // MARK: Decoderen van oudere data (zonder herhaal-velden)

    func testDecodesLegacyReminderWithoutRepeatFields() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"Oud","notes":"","date":782_913_600}"#
            .replacingOccurrences(of: "_", with: "")
        let data = json.data(using: .utf8)!
        let r = try JSONDecoder().decode(CustomReminder.self, from: data)
        XCTAssertEqual(r.repeatRule, .none)
        XCTAssertTrue(r.weekdays.isEmpty)
        XCTAssertFalse(r.isRepeating)
    }
}

private extension CustomReminderTests {
    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }
}
