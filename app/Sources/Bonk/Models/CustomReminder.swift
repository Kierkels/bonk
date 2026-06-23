import Foundation

/// Hoe een herinnering zich herhaalt.
enum ReminderRepeat: String, Codable, CaseIterable, Equatable {
    case none      // eenmalig
    case daily     // elke dag
    case weekdays  // ma t/m vr
    case weekly    // op gekozen weekdagen
}

/// Een zelf toegevoegde herinnering die níét in een agenda staat, maar wel
/// hetzelfde wordt behandeld als een agenda-meeting (regels, menu, waarschuwing).
struct CustomReminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    /// Het eerstvolgende vuurmoment. Voor herhalende herinneringen wordt dit na
    /// het vuren naar de volgende keer opgeschoven (zie `nextOccurrence`).
    var date: Date
    var repeatRule: ReminderRepeat = .none
    /// Weekdagen (1 = zondag … 7 = zaterdag) voor `repeatRule == .weekly`.
    var weekdays: Set<Int> = []

    init(id: UUID = UUID(), title: String = "", notes: String = "", date: Date,
         repeatRule: ReminderRepeat = .none, weekdays: Set<Int> = []) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
        self.repeatRule = repeatRule
        self.weekdays = weekdays
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, date, repeatRule, weekdays
    }

    // Tolerant decoderen: oudere opgeslagen herinneringen kennen de herhaal-velden
    // nog niet → val terug op "eenmalig".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        date = try c.decode(Date.self, forKey: .date)
        repeatRule = try c.decodeIfPresent(ReminderRepeat.self, forKey: .repeatRule) ?? .none
        weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .weekdays) ?? []
    }

    var isRepeating: Bool { repeatRule != .none }

    /// De weekdagen waarop deze herinnering vuurt (1 = zondag … 7 = zaterdag).
    func activeWeekdays(calendar: Calendar = .current) -> Set<Int> {
        switch repeatRule {
        case .none, .daily: return Set(1...7)
        case .weekdays:     return [2, 3, 4, 5, 6]   // ma t/m vr
        case .weekly:
            // Geen dag gekozen → val terug op de weekdag van de ingestelde datum.
            return weekdays.isEmpty ? [calendar.component(.weekday, from: date)] : weekdays
        }
    }

    /// Het eerstvolgende vuurmoment op of na `reference`, met behoud van het
    /// ingestelde tijdstip. Voor eenmalige herinneringen: de datum zelf (of nil
    /// als die al voorbij is).
    func nextOccurrence(onOrAfter reference: Date, calendar: Calendar = .current) -> Date? {
        guard isRepeating else { return date >= reference ? date : nil }
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let days = activeWeekdays(calendar: calendar)
        // Kijk tot 14 dagen vooruit — genoeg voor elke wekelijkse combinatie.
        for offset in 0...14 {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference)),
                  let candidate = calendar.date(bySettingHour: time.hour ?? 9,
                                                minute: time.minute ?? 0,
                                                second: 0, of: dayStart)
            else { continue }
            if candidate < reference { continue }
            if days.contains(calendar.component(.weekday, from: candidate)) { return candidate }
        }
        return nil
    }
}
