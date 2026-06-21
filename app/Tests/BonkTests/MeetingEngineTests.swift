import XCTest
@testable import Bonk

final class MeetingEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)  // vaste "nu"

    // MARK: Negeren & regels

    func testForceShownOverridesDismissed() {
        let e = makeEvent(start: now.addingTimeInterval(300))
        XCTAssertFalse(MeetingEngine.isIgnored(e, rules: [makeRule()],
                                               dismissed: [e.id], forceShown: [e.id]))
    }

    func testDismissedIsIgnored() {
        let e = makeEvent(start: now.addingTimeInterval(300))
        XCTAssertTrue(MeetingEngine.isIgnored(e, rules: [makeRule()],
                                              dismissed: [e.id], forceShown: []))
    }

    func testIgnoreRuleMakesEventIgnored() {
        let e = makeEvent(start: now.addingTimeInterval(300))
        XCTAssertTrue(MeetingEngine.isIgnored(e, rules: [makeRule(alertStyle: .ignore)],
                                              dismissed: [], forceShown: []))
    }

    func testWarnRulePicksFirstNonIgnoreMatch() {
        let e = makeEvent(start: now.addingTimeInterval(300))
        let rules = [makeRule(name: "negeer", alertStyle: .ignore, titleContains: "standup"),
                     makeRule(name: "alle", alertStyle: .banner)]
        // Titel matcht de negeer-regel niet → valt door naar de banner-regel.
        let rule = MeetingEngine.warnRule(for: e, rules: rules, dismissed: [], forceShown: [])
        XCTAssertEqual(rule?.name, "alle")
    }

    func testWarnRuleNilWhenFirstMatchIsIgnore() {
        let e = makeEvent(title: "Standup", start: now.addingTimeInterval(300))
        let rules = [makeRule(name: "negeer", alertStyle: .ignore, titleContains: "standup"),
                     makeRule(name: "alle", alertStyle: .banner)]
        XCTAssertNil(MeetingEngine.warnRule(for: e, rules: rules, dismissed: [], forceShown: []))
    }

    // MARK: Classificatie

    func testClassifySplitsUpcomingEndedAndIgnored() {
        let live = makeEvent(id: "live", start: now.addingTimeInterval(300))
        let ended = makeEvent(id: "ended", start: now.addingTimeInterval(-3600))  // al voorbij
        let ignored = makeEvent(id: "ign", start: now.addingTimeInterval(600))
        let c = MeetingEngine.classify(events: [live, ended, ignored], now: now,
                                       rules: [makeRule()], dismissed: ["ign"], forceShown: [])
        XCTAssertEqual(c.upcoming.map(\.id), ["live"])
        XCTAssertEqual(c.skipped.map(\.id), ["ign"])
        XCTAssertEqual(c.next?.id, "live")
    }

    // MARK: Vuren & snooze

    func testFiresInsideWindow() {
        let e = makeEvent(start: now.addingTimeInterval(60))   // start over 1 min
        let rule = makeRule(leadMinutes: 2)                    // venster opent 2 min vooraf
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: now,
                                              snoozeUntil: nil, alreadyFired: false), .fire)
    }

    func testDoesNotFireBeforeWindow() {
        let e = makeEvent(start: now.addingTimeInterval(600))  // start over 10 min
        let rule = makeRule(leadMinutes: 2)
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: now,
                                              snoozeUntil: nil, alreadyFired: false), .none)
    }

    func testDoesNotFireWhenAlreadyFired() {
        let e = makeEvent(start: now.addingTimeInterval(60))
        let rule = makeRule(leadMinutes: 2)
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: now,
                                              snoozeUntil: nil, alreadyFired: true), .none)
    }

    func testStillSnoozed() {
        let e = makeEvent(start: now.addingTimeInterval(60))
        let rule = makeRule()
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: now,
                                              snoozeUntil: now.addingTimeInterval(120),
                                              alreadyFired: true), .stillSnoozed)
    }

    /// Regressietest: snooze van 5 min op een melding 2 min vóór de start moet ná
    /// de snooze terugkomen, óók als dat voorbij `start + 2 min` valt.
    func testSnoozeReturnsAfterGraceWindow() {
        let start = now.addingTimeInterval(120)               // start over 2 min
        let e = makeEvent(start: start, durationMin: 30)
        let rule = makeRule(leadMinutes: 2)
        let afterSnooze = now.addingTimeInterval(300)         // 5 min later (= start + 3 min)
        // Snooze net afgelopen, meeting loopt nog → opnieuw tonen.
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: afterSnooze,
                                              snoozeUntil: now.addingTimeInterval(300),
                                              alreadyFired: false), .snoozeEnded(fire: true))
    }

    func testSnoozeEndedButMeetingOver() {
        let e = makeEvent(start: now.addingTimeInterval(-3600), durationMin: 30)  // al afgelopen
        let rule = makeRule()
        XCTAssertEqual(MeetingEngine.decision(for: e, rule: rule, now: now,
                                              snoozeUntil: now.addingTimeInterval(-10),
                                              alreadyFired: false), .snoozeEnded(fire: false))
    }

    // MARK: Markering

    private func settings(highlight: Bool = true, minutes: Int = 5,
                          mode: String = "calendar", onlyToday: Bool = false,
                          enabled: Bool = true) -> AppSettings {
        var s = AppSettings.default
        s.globalEnabled = enabled
        s.menuBarHighlightEnabled = highlight
        s.menuBarHighlightMinutes = minutes
        s.menuBarHighlightColorMode = mode
        s.menuBarOnlyToday = onlyToday
        return s
    }

    func testHighlightNoneWhenDisabled() {
        let n = makeEvent(start: now.addingTimeInterval(60))
        XCTAssertEqual(MeetingEngine.highlightChoice(next: n, upcoming: [n], now: now,
                                                     settings: settings(highlight: false)), .none)
    }

    func testHighlightNoneBeyondThreshold() {
        let n = makeEvent(start: now.addingTimeInterval(20 * 60))  // 20 min weg
        XCTAssertEqual(MeetingEngine.highlightChoice(next: n, upcoming: [n], now: now,
                                                     settings: settings(minutes: 5)), .none)
    }

    func testHighlightCustom() {
        let n = makeEvent(start: now.addingTimeInterval(60))
        XCTAssertEqual(MeetingEngine.highlightChoice(next: n, upcoming: [n], now: now,
                                                     settings: settings(mode: "custom")), .custom)
    }

    func testHighlightCalendarColourForSingle() {
        let n = makeEvent(start: now.addingTimeInterval(60), calendarID: "cal-A")
        XCTAssertEqual(MeetingEngine.highlightChoice(next: n, upcoming: [n], now: now,
                                                     settings: settings()), .calendar("cal-A"))
    }

    func testHighlightWhiteForMultipleCalendarsAtOnce() {
        let a = makeEvent(id: "a", start: now.addingTimeInterval(60), calendarID: "cal-A")
        let b = makeEvent(id: "b", start: now.addingTimeInterval(80), calendarID: "cal-B")  // <60s verschil
        XCTAssertEqual(MeetingEngine.highlightChoice(next: a, upcoming: [a, b], now: now,
                                                     settings: settings()), .white)
    }

    func testHighlightWorksForReminder() {
        let r = makeEvent(id: "reminder:abc", start: now.addingTimeInterval(60), calendarID: "bonk.reminder")
        XCTAssertEqual(MeetingEngine.highlightChoice(next: r, upcoming: [r], now: now,
                                                     settings: settings()), .calendar("bonk.reminder"))
    }

    // MARK: Herinnering-ids

    func testReminderIDParsing() {
        let uuid = UUID()
        XCTAssertEqual(MeetingEngine.reminderUUID(fromEventID: "reminder:\(uuid.uuidString)"), uuid)
        XCTAssertNil(MeetingEngine.reminderUUID(fromEventID: "evt-123"))
        XCTAssertTrue(MeetingEngine.isReminderID("reminder:x"))
        XCTAssertFalse(MeetingEngine.isReminderID("evt-1"))
    }

    // MARK: Agenda-selectie (leeg = niets)

    func testEmptySelectionMeansNoCalendars() {
        XCTAssertTrue(MeetingEngine.selectedCalendarIDs(available: ["A", "B"], enabled: []).isEmpty)
    }

    func testSelectionFiltersToEnabled() {
        XCTAssertEqual(MeetingEngine.selectedCalendarIDs(available: ["A", "B", "C"], enabled: ["A", "C"]),
                       ["A", "C"])
    }
}
