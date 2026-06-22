import Foundation

/// Pure beslis-logica van Bonk — géén UI, AppKit, EventKit of tijd-als-side-effect.
/// Alles hier is `static` en deterministisch (tijd komt binnen als parameter),
/// zodat het volledig te unit-testen is. De `AppDelegate` mag hier alleen naar
/// delegeren; zo testen de tests het écht gebruikte gedrag.
enum MeetingEngine {

    // MARK: - Negeren & regels

    /// Wordt deze afspraak genegeerd? Handmatig genegeerd, óf de eerste passende
    /// regel is een negeer-regel — tenzij hij expliciet weer geactiveerd is.
    static func isIgnored(_ e: UpcomingEvent,
                          rules: [MeetingRule],
                          dismissed: Set<String>,
                          forceShown: Set<String>) -> Bool {
        if forceShown.contains(e.id) { return false }
        if dismissed.contains(e.id) { return true }
        return rules.first(where: { $0.matches(e) })?.alertStyle == .ignore
    }

    /// De regel die bepaalt hoe gewaarschuwd wordt (nil = niet waarschuwen).
    static func warnRule(for e: UpcomingEvent,
                         rules: [MeetingRule],
                         dismissed: Set<String>,
                         forceShown: Set<String>) -> MeetingRule? {
        guard !isIgnored(e, rules: rules, dismissed: dismissed, forceShown: forceShown) else { return nil }
        return rules.first { $0.alertStyle != .ignore && $0.matches(e) }
    }

    /// De getoonde lijsten: waar wél voor gewaarschuwd wordt, en de genegeerde.
    /// `events` wordt verondersteld op starttijd gesorteerd te zijn → `next` = eerste.
    struct Classification: Equatable {
        var upcoming: [UpcomingEvent]
        var skipped: [UpcomingEvent]
        var next: UpcomingEvent? { upcoming.first }
    }

    static func classify(events: [UpcomingEvent],
                         now: Date,
                         rules: [MeetingRule],
                         dismissed: Set<String>,
                         forceShown: Set<String>) -> Classification {
        let upcoming = events.filter {
            $0.end > now && warnRule(for: $0, rules: rules, dismissed: dismissed, forceShown: forceShown) != nil
        }
        let skipped = events.filter {
            $0.end > now && isIgnored($0, rules: rules, dismissed: dismissed, forceShown: forceShown)
        }
        return Classification(upcoming: upcoming, skipped: skipped)
    }

    /// Wat er in het menu staat: agenda-meetings volgen de regels, herinneringen
    /// staan **altijd** in "volgende" (los van de regels, en nooit in "genegeerd").
    static func visibleEvents(calendarEvents: [UpcomingEvent],
                              reminders: [UpcomingEvent],
                              now: Date,
                              rules: [MeetingRule],
                              dismissed: Set<String>,
                              forceShown: Set<String>) -> Classification {
        let cal = classify(events: calendarEvents, now: now, rules: rules,
                           dismissed: dismissed, forceShown: forceShown)
        let liveReminders = reminders.filter { $0.end > now }
        let upcoming = (cal.upcoming + liveReminders).sorted { $0.start < $1.start }
        return Classification(upcoming: upcoming, skipped: cal.skipped)
    }

    /// Beperkt een (op starttijd gesorteerde) lijst tot wat het menu/de menubalk
    /// toont: een dagvenster van `days` dagen (1 = alleen vandaag) en optioneel een
    /// maximum aantal **agenda-meetings** (`maxMeetings`, nil = alle). Herinneringen
    /// tellen niet mee voor het maximum en blijven altijd zichtbaar binnen het venster.
    /// Dit raakt alléén de weergave — niet het vuren van waarschuwingen.
    static func displayLimited(_ events: [UpcomingEvent], now: Date,
                               days: Int, maxMeetings: Int?,
                               calendar: Calendar = .current) -> [UpcomingEvent] {
        let startOfToday = calendar.startOfDay(for: now)
        let windowEnd = calendar.date(byAdding: .day, value: max(1, days), to: startOfToday) ?? now
        let inWindow = events.filter { $0.start < windowEnd }
        guard let maxMeetings, maxMeetings >= 0 else { return inWindow }
        var meetingCount = 0
        return inWindow.filter { e in
            if isReminderID(e.id) { return true }
            meetingCount += 1
            return meetingCount <= maxMeetings
        }
    }

    // MARK: - Vuren & snooze

    enum AlertDecision: Equatable {
        case none                       // buiten venster of al gevuurd
        case stillSnoozed               // snooze loopt nog
        case fire                       // tonen
        case snoozeEnded(fire: Bool)    // snooze voorbij: `fire` als de meeting nog loopt
    }

    /// Beslis of een afspraak nú getoond moet worden. Snooze-afloop is een eigen
    /// trigger (los van het normale venster), zodat een snooze die voorbij
    /// `start + 2 min` valt alsnog terugkomt.
    static func decision(for e: UpcomingEvent,
                         rule: MeetingRule,
                         now: Date,
                         snoozeUntil: Date?,
                         alreadyFired: Bool) -> AlertDecision {
        if let snz = snoozeUntil {
            if now < snz { return .stillSnoozed }
            return .snoozeEnded(fire: e.end > now)
        }
        let fireTime = e.start.addingTimeInterval(-Double(rule.leadMinutes) * 60)
        let grace = e.start.addingTimeInterval(120)
        if now >= fireTime, now <= grace, !alreadyFired { return .fire }
        return .none
    }

    /// Het eerstvolgende moment waarop er iets moet afgaan (vuurtijd van de
    /// eerstvolgende waarschuwing, of het einde van een snooze). Hiermee kan een
    /// exacte timer worden gezet zodat een waarschuwing vrijwel op de seconde komt
    /// i.p.v. pas bij de volgende periodieke controle. Nil = niets gepland.
    static func nextWake(events: [UpcomingEvent],
                         now: Date,
                         rules: [MeetingRule],
                         dismissed: Set<String>,
                         forceShown: Set<String>,
                         reminderRule: MeetingRule,
                         snoozeUntil: [String: Date]) -> Date? {
        var soonest: Date? = nil
        for e in events {
            let rule: MeetingRule?
            if isReminderID(e.id) {
                rule = reminderRule.alertStyle == .ignore ? nil : reminderRule
            } else {
                rule = warnRule(for: e, rules: rules, dismissed: dismissed, forceShown: forceShown)
            }
            guard let rule else { continue }

            let candidate: Date?
            if let snz = snoozeUntil[e.id], snz > now {
                candidate = snz
            } else {
                let fireTime = e.start.addingTimeInterval(-Double(rule.leadMinutes) * 60)
                candidate = fireTime > now ? fireTime : nil
            }
            if let c = candidate { soonest = soonest.map { min($0, c) } ?? c }
        }
        return soonest
    }

    // MARK: - Menubalk-markering

    enum HighlightChoice: Equatable {
        case none
        case custom              // gebruik de eigen kleur uit de instellingen
        case white               // meerdere meetings tegelijk uit verschillende agenda's
        case calendar(String)    // agenda-id (kleur opzoeken bij de agenda)
    }

    static func highlightChoice(next: UpcomingEvent?,
                                upcoming: [UpcomingEvent],
                                now: Date,
                                settings: AppSettings) -> HighlightChoice {
        guard settings.globalEnabled, settings.menuBarHighlightEnabled, let n = next else { return .none }
        // (Het dagvenster is al toegepast op `next`/`upcoming` via `displayLimited`.)
        let minutesUntil = n.start.timeIntervalSince(now) / 60
        guard minutesUntil <= Double(settings.menuBarHighlightMinutes) else { return .none }

        if settings.menuBarHighlightColorMode == "custom" { return .custom }
        let simultaneous = upcoming.filter { abs($0.start.timeIntervalSince(n.start)) < 60 }
        if Set(simultaneous.map { $0.calendarID }).count > 1 { return .white }
        return .calendar(n.calendarID)
    }

    // MARK: - Herinneringen

    /// Vaste id voor de pseudo-regel van herinneringen (stabiel voor `firedKeys`-dedup).
    static let reminderRuleID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// De waarschuwingsregel die herinneringen volgen, afgeleid van de globale
    /// herinnering-instellingen (níét van de meeting-regels).
    static func reminderRule(from s: AppSettings) -> MeetingRule {
        var r = MeetingRule()
        r.id = reminderRuleID
        r.name = "__reminder__"
        r.alertStyle = s.reminderAlertStyle
        r.leadMinutes = s.reminderLeadMinutes
        r.appearanceID = s.reminderAppearanceID
        r.notificationSound = s.reminderSound
        r.notifyWhenLocked = s.reminderNotifyWhenLocked
        r.repeatSound = s.reminderRepeatSound
        r.soundMaxSeconds = s.reminderSoundMaxSeconds
        r.overrideMute = s.reminderOverrideMute
        return r
    }

    static let reminderIDPrefix = "reminder:"

    static func isReminderID(_ id: String) -> Bool { id.hasPrefix(reminderIDPrefix) }

    /// Haalt het herinnering-UUID uit een event-id `"reminder:<uuid>"` (nil als het
    /// geen herinnering is of het UUID niet klopt).
    static func reminderUUID(fromEventID id: String) -> UUID? {
        guard id.hasPrefix(reminderIDPrefix) else { return nil }
        return UUID(uuidString: String(id.dropFirst(reminderIDPrefix.count)))
    }

    // MARK: - Agenda-selectie

    /// Welke agenda's gevolgd worden: doorsnede van beschikbaar en ingeschakeld.
    /// Lege selectie ⇒ lege uitkomst ⇒ geen agenda-meetings.
    static func selectedCalendarIDs(available: [String], enabled: Set<String>) -> [String] {
        available.filter { enabled.contains($0) }
    }
}
