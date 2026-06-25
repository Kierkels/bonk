import Foundation

/// RSVP-/aanwezigheidsstatus van een afspraak voor de huidige gebruiker.
enum Attendance: String, Codable, CaseIterable {
    case accepted        // jij hebt geaccepteerd (of voorlopig/tentative)
    case invited         // uitgenodigd, nog niet gereageerd
    case declined        // jij hebt afgewezen
    case informational   // geen persoonlijke RSVP (gedeelde/jaarkalender, of jij niet als genodigde)
    case none            // niet van toepassing (bv. herinneringen) — geen badge

    /// Categorieën die je in een regelfilter kunt kiezen (`.none` hoort daar niet bij).
    static let filterChoices: [Attendance] = [.accepted, .invited, .informational, .declined]

    func label(_ lang: Lang) -> String {
        switch self {
        case .accepted:      return L("Geaccepteerd", "Accepted", lang)
        case .invited:       return L("Uitgenodigd", "Invited", lang)
        case .declined:      return L("Afgewezen", "Declined", lang)
        case .informational: return L("Ter info", "For info", lang)
        case .none:          return ""
        }
    }

    var icon: String {
        switch self {
        case .accepted:      return "checkmark.circle.fill"
        case .invited:       return "envelope.circle.fill"
        case .declined:      return "xmark.circle.fill"
        case .informational: return "info.circle.fill"
        case .none:          return ""
        }
    }

    /// Toont de badge alleen voor echte RSVP-/info-statussen (niet bij `.none`).
    var showsBadge: Bool { self != .none }
}

/// Een genormaliseerde, UI-vriendelijke weergave van een agenda-afspraak.
struct UpcomingEvent: Identifiable, Equatable {
    let id: String            // stabiel per afspraak-occurrence
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
    let calendarID: String
    let attendance: Attendance
    let joinURL: URL?
    let location: String?
    let notes: String?
    let weekday: Int          // 1 = zondag ... 7 = zaterdag (Calendar.weekday)
    /// Link om de afspraak in de agenda te openen: de web-link van het event
    /// (bv. Google Calendar `htmlLink`) als die er is, anders een
    /// `ical://ekevent/…`-link naar de macOS Agenda-app. Nil voor herinneringen.
    var calendarItemURL: URL? = nil
}
