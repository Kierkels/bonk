import Foundation
import EventKit
import Combine

/// Praat met EventKit: vraagt toegang en levert genormaliseerde afspraken.
@MainActor
final class CalendarManager: ObservableObject {
    let store = EKEventStore()
    @Published var authorized = false
    @Published var calendars: [EKCalendar] = []

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            authorized = granted
            if granted { calendars = store.calendars(for: .event) }
        } catch {
            authorized = false
        }
    }

    func upcomingEvents(within hours: Int, enabledCalendarIDs: Set<String>) -> [UpcomingEvent] {
        guard authorized else { return [] }
        // Trek externe wijzigingen (bv. gesyncte Google-agenda) actief bij.
        store.refreshSourcesIfNecessary()
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now

        // Leeg = geen agenda's volgen.
        let cals = store.calendars(for: .event).filter { enabledCalendarIDs.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: cals)
        let cal = Calendar.current

        return store.events(matching: predicate)
            .compactMap { ev -> UpcomingEvent? in
                guard !ev.isAllDay, let start = ev.startDate else { return nil }
                // Houd toekomstige én lopende meetings (nog niet afgelopen).
                guard (ev.endDate ?? start) > now else { return nil }
                if ev.status == .canceled { return nil }

                let url = LinkDetector.firstURL(in: [ev.notes, ev.location, ev.url?.absoluteString])
                let id = (ev.eventIdentifier ?? UUID().uuidString)
                    + "@" + String(Int(start.timeIntervalSince1970))

                return UpcomingEvent(
                    id: id,
                    title: ev.title ?? "Meeting",
                    start: start,
                    end: ev.endDate ?? start,
                    calendarTitle: ev.calendar?.title ?? "",
                    calendarID: ev.calendar?.calendarIdentifier ?? "",
                    isAccepted: Self.isAccepted(ev),
                    joinURL: url,
                    location: ev.location,
                    notes: Self.cleanNotes(ev.notes),
                    weekday: cal.component(.weekday, from: start)
                )
            }
            .sorted { $0.start < $1.start }
    }

    /// Strip de automatisch toegevoegde conferencing-boilerplate (Google/Teams)
    /// en HTML, zodat alleen de door de organisator getypte omschrijving overblijft.
    static func cleanNotes(_ raw: String?) -> String? {
        guard var text = raw else { return nil }

        // Google scheidt de eigen omschrijving van de boilerplate met een lange
        // "-::~:~::~..."-regel; knip daar (en bij Teams-markers) af.
        for marker in ["-::~:~", "________________________________________________________________________________",
                       "Microsoft Teams", "Join on your computer", "Vergaderings-id:"] {
            if let r = text.range(of: marker) {
                text = String(text[..<r.lowerBound])
            }
        }

        // Eenvoudige HTML-strip + entiteiten.
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        // Lege regels samenvoegen en trimmen.
        let collapsed = text
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? nil : collapsed
    }

    /// Beschouw afspraken zonder deelnemers (eigen events) als geaccepteerd.
    static func isAccepted(_ ev: EKEvent) -> Bool {
        guard let attendees = ev.attendees, !attendees.isEmpty else { return true }
        if let me = attendees.first(where: { $0.isCurrentUser }) {
            switch me.participantStatus {
            case .accepted, .tentative: return true
            default: return false
            }
        }
        return true
    }
}
