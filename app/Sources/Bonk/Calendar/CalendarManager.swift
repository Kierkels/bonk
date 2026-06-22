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
            if granted { reloadCalendars() }
        } catch {
            authorized = false
        }
    }

    /// Ververst de lijst met beschikbare agenda's (gesorteerd op naam). Nodig
    /// omdat agenda's na de eerste laadbeurt kunnen wijzigen (nieuwe/gesyncte/
    /// geabonneerde agenda's) — anders mist de UI ze tot een herstart.
    func reloadCalendars() {
        guard authorized else { return }
        store.refreshSourcesIfNecessary()
        calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func upcomingEvents(within hours: Int, enabledCalendarIDs: Set<String>) -> [UpcomingEvent] {
        guard authorized else { return [] }
        // Trek externe wijzigingen (bv. gesyncte Google-agenda) actief bij.
        store.refreshSourcesIfNecessary()
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) ?? now

        // Leeg = geen agenda's volgen.
        let all = store.calendars(for: .event)
        let selected = Set(MeetingEngine.selectedCalendarIDs(available: all.map { $0.calendarIdentifier },
                                                             enabled: enabledCalendarIDs))
        let cals = all.filter { selected.contains($0.calendarIdentifier) }
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
                    attendance: Self.attendance(ev),
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
    nonisolated static func cleanNotes(_ raw: String?) -> String? {
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

    /// Bepaalt de RSVP-status van de huidige gebruiker. Events zónder persoonlijke
    /// uitnodiging (geen deelnemers, of jij staat niet in de lijst — zoals gedeelde/
    /// jaarkalender-items) zijn `.informational`, niet "geaccepteerd".
    static func attendance(_ ev: EKEvent) -> Attendance {
        // Bij een gedeelde agenda injecteert EventKit de agenda zélf als
        // `isCurrentUser`-deelnemer (status accepted) — dat is géén persoonlijke
        // RSVP. Negeer die proxy (naam == agenda-titel) en zoek een échte
        // jij-deelnemer; anders → informational.
        let calendarTitle = ev.calendar?.title
        guard let me = (ev.attendees ?? []).first(where: {
            $0.isCurrentUser && $0.name != calendarTitle
        }) else {
            return .informational
        }
        switch me.participantStatus {
        case .accepted, .tentative: return .accepted
        case .declined:             return .declined
        default:                    return .invited   // pending / unknown / needs-action
        }
    }
}
