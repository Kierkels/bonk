import Foundation

/// Een genormaliseerde, UI-vriendelijke weergave van een agenda-afspraak.
struct UpcomingEvent: Identifiable, Equatable {
    let id: String            // stabiel per afspraak-occurrence
    let title: String
    let start: Date
    let end: Date
    let calendarTitle: String
    let calendarID: String
    let isAccepted: Bool
    let joinURL: URL?
    let location: String?
    let notes: String?
    let weekday: Int          // 1 = zondag ... 7 = zaterdag (Calendar.weekday)
}
