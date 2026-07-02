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

    // MARK: Herinneringen los van regels

    func testRemindersAlwaysUpcomingIgnoringRules() {
        let reminder = makeEvent(id: "reminder:1", title: "Koken", start: now.addingTimeInterval(300), calendarID: "bonk.reminder")
        let meeting = makeEvent(id: "m1", title: "Koken", start: now.addingTimeInterval(300), calendarID: "work")
        let rules = [makeRule(alertStyle: .ignore, titleContains: "koken")]   // negeert alles met "koken"
        let c = MeetingEngine.visibleEvents(calendarEvents: [meeting], reminders: [reminder],
                                            now: now, rules: rules, dismissed: [], forceShown: [])
        XCTAssertTrue(c.upcoming.contains { $0.id == "reminder:1" })   // herinnering tóch zichtbaar
        XCTAssertFalse(c.upcoming.contains { $0.id == "m1" })          // meeting door regel genegeerd
        XCTAssertFalse(c.skipped.contains { $0.id == "reminder:1" })   // herinnering nooit in "genegeerd"
    }

    func testPastReminderStaysVisible() {
        // Een gesnoozede herinnering heeft een weergavetijd in het verleden, maar moet
        // zichtbaar blijven in de lijst (anders verdwijnt 'ie tijdens de snooze).
        let past = makeEvent(id: "reminder:1", start: now.addingTimeInterval(-300),
                             durationMin: 0, calendarID: "bonk.reminder")
        let c = MeetingEngine.visibleEvents(calendarEvents: [], reminders: [past],
                                            now: now, rules: [makeRule()], dismissed: [], forceShown: [])
        XCTAssertTrue(c.upcoming.contains { $0.id == "reminder:1" })
    }

    func testReminderRuleMapsGlobalSettings() {
        var s = AppSettings.default
        s.reminderAlertStyle = .banner
        s.reminderLeadMinutes = 0
        s.reminderSound = "Glass"
        s.reminderNotifyWhenLocked = true
        s.reminderRepeatSound = true
        let r = MeetingEngine.reminderRule(from: s)
        XCTAssertEqual(r.id, MeetingEngine.reminderRuleID)
        XCTAssertEqual(r.alertStyle, .banner)
        XCTAssertEqual(r.leadMinutes, 0)
        XCTAssertEqual(r.notificationSound, "Glass")
        XCTAssertTrue(r.notifyWhenLocked)
        XCTAssertTrue(r.repeatSound)
    }

    func testReminderLeadZeroFiresAtStart() {
        let reminder = makeEvent(id: "reminder:1", start: now, calendarID: "bonk.reminder")
        var s = AppSettings.default; s.reminderLeadMinutes = 0
        let rule = MeetingEngine.reminderRule(from: s)
        XCTAssertEqual(MeetingEngine.decision(for: reminder, rule: rule, now: now,
                                              snoozeUntil: nil, alreadyFired: false), .fire)
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

    // MARK: Exacte wektijd

    func testNextWakeReminderLeadZeroIsStart() {
        let r = makeEvent(id: "reminder:1", start: now.addingTimeInterval(120), calendarID: "bonk.reminder")
        var s = AppSettings.default; s.reminderLeadMinutes = 0
        let wake = MeetingEngine.nextWake(events: [r], now: now, rules: [], dismissed: [], forceShown: [],
                                          reminderRule: MeetingEngine.reminderRule(from: s), snoozeUntil: [:])
        XCTAssertEqual(wake, r.start)   // lead 0 → vuurmoment = starttijd
    }

    func testNextWakePicksSoonestFireTime() {
        let m = makeEvent(id: "m1", start: now.addingTimeInterval(600))                        // +10 min
        let r = makeEvent(id: "reminder:1", start: now.addingTimeInterval(900), calendarID: "bonk.reminder")  // +15 min
        let rule = makeRule(leadMinutes: 5)   // meeting vuurt op +5 min
        var s = AppSettings.default; s.reminderLeadMinutes = 0
        let wake = MeetingEngine.nextWake(events: [m, r], now: now, rules: [rule], dismissed: [], forceShown: [],
                                          reminderRule: MeetingEngine.reminderRule(from: s), snoozeUntil: [:])
        XCTAssertEqual(wake, now.addingTimeInterval(300))   // +5 min is het vroegst
    }

    func testNextWakeNilWhenAlreadyInWindow() {
        let m = makeEvent(id: "m1", start: now.addingTimeInterval(30))   // lead 2min → vuurtijd al gepasseerd
        let rule = makeRule(leadMinutes: 2)
        let wake = MeetingEngine.nextWake(events: [m], now: now, rules: [rule], dismissed: [], forceShown: [],
                                          reminderRule: MeetingEngine.reminderRule(from: .default), snoozeUntil: [:])
        XCTAssertNil(wake)   // niets te plannen; vuurt al via de normale controle
    }

    // MARK: Markering

    private func settings(highlight: Bool = true, minutes: Int = 5,
                          mode: String = "calendar",
                          enabled: Bool = true) -> AppSettings {
        var s = AppSettings.default
        s.globalEnabled = enabled
        s.menuBarHighlightEnabled = highlight
        s.menuBarHighlightMinutes = minutes
        s.menuBarHighlightColorMode = mode
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

    // MARK: Dagvenster + maximum (displayLimited)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testDisplayLimitedTodayOnlyDropsTomorrow() {
        let sod = utc.startOfDay(for: now)
        let today = makeEvent(id: "today", start: sod.addingTimeInterval(12 * 3600))
        let tomorrow = makeEvent(id: "tomorrow", start: sod.addingTimeInterval(36 * 3600))
        let out = MeetingEngine.displayLimited([today, tomorrow], now: now, days: 1, maxMeetings: nil, calendar: utc)
        XCTAssertEqual(out.map { $0.id }, ["today"])
    }

    func testDisplayLimitedTwoDaysKeepsTomorrowNotDayAfter() {
        let sod = utc.startOfDay(for: now)
        let today = makeEvent(id: "today", start: sod.addingTimeInterval(12 * 3600))
        let tomorrow = makeEvent(id: "tomorrow", start: sod.addingTimeInterval(36 * 3600))
        let dayAfter = makeEvent(id: "after", start: sod.addingTimeInterval(60 * 3600))
        let out = MeetingEngine.displayLimited([today, tomorrow, dayAfter], now: now, days: 2, maxMeetings: nil, calendar: utc)
        XCTAssertEqual(out.map { $0.id }, ["today", "tomorrow"])
    }

    func testDisplayLimitedMaxCountsMeetingsButAlwaysKeepsReminders() {
        let sod = utc.startOfDay(for: now)
        let m1 = makeEvent(id: "m1", start: sod.addingTimeInterval(9 * 3600))
        let r1 = makeEvent(id: "reminder:1", start: sod.addingTimeInterval(10 * 3600), calendarID: "bonk.reminder")
        let m2 = makeEvent(id: "m2", start: sod.addingTimeInterval(11 * 3600))
        let m3 = makeEvent(id: "m3", start: sod.addingTimeInterval(12 * 3600))
        let r2 = makeEvent(id: "reminder:2", start: sod.addingTimeInterval(13 * 3600), calendarID: "bonk.reminder")
        let out = MeetingEngine.displayLimited([m1, r1, m2, m3, r2], now: now, days: 1, maxMeetings: 2, calendar: utc)
        // Max 2 meetings → m1 & m2 blijven (m3 valt af); beide herinneringen blijven.
        XCTAssertEqual(out.map { $0.id }, ["m1", "reminder:1", "m2", "reminder:2"])
    }

    func testDisplayLimitedNilMaxKeepsAllMeetings() {
        let sod = utc.startOfDay(for: now)
        let evts = (0..<6).map { makeEvent(id: "m\($0)", start: sod.addingTimeInterval(Double(9 + $0) * 3600)) }
        let out = MeetingEngine.displayLimited(evts, now: now, days: 1, maxMeetings: nil, calendar: utc)
        XCTAssertEqual(out.count, 6)
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

    // MARK: Snooze tot start

    func testSnoozeUntilStartStillSnoozedBeforeStart() {
        let meetingStart = now.addingTimeInterval(120)
        let meeting = makeEvent(start: meetingStart)
        let decision = MeetingEngine.decision(for: meeting, rule: makeRule(), now: now,
                                              snoozeUntil: meetingStart, alreadyFired: true)
        XCTAssertEqual(decision, .stillSnoozed)
    }

    func testSnoozeUntilStartFiresMeetingAtStart() {
        let meeting = makeEvent(start: now, durationMin: 30)
        let decision = MeetingEngine.decision(for: meeting, rule: makeRule(), now: now,
                                              snoozeUntil: now, alreadyFired: true)
        XCTAssertEqual(decision, .snoozeEnded(fire: true))
    }

    func testSnoozeUntilStartFiresReminderAtStartWithinGrace() {
        // Momentpunt (reminder): end == start. Net na de start, binnen de grace → vuren.
        let reminder = makeEvent(id: "reminder:abc", start: now.addingTimeInterval(-5), durationMin: 0)
        let decision = MeetingEngine.decision(for: reminder, rule: makeRule(), now: now,
                                              snoozeUntil: now.addingTimeInterval(-5), alreadyFired: true)
        XCTAssertEqual(decision, .snoozeEnded(fire: true))
    }

    func testSnoozeUntilStartReminderStillFiresAfterGrace() {
        // Een gesnoozede herinnering mag niet verdwijnen als de tick laat komt:
        // ook ruim na de starttijd vuurt 'ie alsnog zodra de snooze afloopt.
        let reminder = makeEvent(id: "reminder:abc", start: now.addingTimeInterval(-200), durationMin: 0)
        let decision = MeetingEngine.decision(for: reminder, rule: makeRule(), now: now,
                                              snoozeUntil: now.addingTimeInterval(-200), alreadyFired: true)
        XCTAssertEqual(decision, .snoozeEnded(fire: true))
    }

    // MARK: Compacte aftelling (menubalk)

    /// "nu" op UTC-middernacht zodat dag-grenzen deterministisch zijn (hergebruikt `utc`).
    private func cdNow() -> Date {
        utc.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 0, minute: 0))!
    }
    private func compact(_ interval: TimeInterval, _ lang: Lang = .nl) -> String {
        let now = cdNow()
        return MeetingEngine.compactCountdown(to: now.addingTimeInterval(interval),
                                              now: now, calendar: utc, lang: lang)
    }

    func testCompactCountdownMinutesAndNow() {
        XCTAssertEqual(compact(-30), "bezig")
        XCTAssertEqual(compact(30), "nu")
        XCTAssertEqual(compact(45 * 60), "in 45m")
    }

    /// De aanleiding: 1u33m mag niet naar "in 1u" afkappen.
    func testCompactCountdownShowsHoursAndMinutes() {
        XCTAssertEqual(compact(93 * 60), "in 1u33")
        XCTAssertEqual(compact(93 * 60, .en), "in 1h33")
        // Minuten nul-gevuld, zodat "1u03" niet als "1u30" leest.
        XCTAssertEqual(compact((60 + 3) * 60), "in 1u03")
    }

    func testCompactCountdownExactHourHasNoMinutes() {
        XCTAssertEqual(compact(2 * 3600), "in 2u")
        XCTAssertEqual(compact(2 * 3600, .en), "in 2h")
    }

    /// Uren+minuten blijven precies tot vlak onder een dag (geen afronding meer).
    func testCompactCountdownPreciseUpToADay() {
        XCTAssertEqual(compact((4 * 60 + 10) * 60), "in 4u10")
        XCTAssertEqual(compact((12 * 60 + 5) * 60), "in 12u05")
        XCTAssertEqual(compact((23 * 60 + 59) * 60), "in 23u59")
    }

    func testCompactCountdownDaysUseWords() {
        // Zelfde tijdstip morgen / overmorgen (UTC-middernacht → hele dagen).
        XCTAssertEqual(compact(24 * 3600), "morgen")
        XCTAssertEqual(compact(24 * 3600, .en), "tomorrow")
        XCTAssertEqual(compact(48 * 3600), "over 2 dagen")
        XCTAssertEqual(compact(72 * 3600, .en), "in 3 days")
    }

    /// Vlak ná middernacht (< 1 dag) blijft het gewoon minuten, geen "morgen".
    func testCompactCountdownAcrossMidnightStaysPrecise() {
        let now = utc.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 23, minute: 58))!
        let target = now.addingTimeInterval(4 * 60)   // 00:02 de volgende dag
        XCTAssertEqual(MeetingEngine.compactCountdown(to: target, now: now, calendar: utc, lang: .nl), "in 4m")
    }
}
