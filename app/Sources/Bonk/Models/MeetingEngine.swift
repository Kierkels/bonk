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
        if settings.menuBarOnlyToday, !Calendar.current.isDate(n.start, inSameDayAs: now) { return .none }
        let minutesUntil = n.start.timeIntervalSince(now) / 60
        guard minutesUntil <= Double(settings.menuBarHighlightMinutes) else { return .none }

        if settings.menuBarHighlightColorMode == "custom" { return .custom }
        let simultaneous = upcoming.filter { abs($0.start.timeIntervalSince(n.start)) < 60 }
        if Set(simultaneous.map { $0.calendarID }).count > 1 { return .white }
        return .calendar(n.calendarID)
    }

    // MARK: - Herinneringen

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
