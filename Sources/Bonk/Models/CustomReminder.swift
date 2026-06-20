import Foundation

/// Een zelf toegevoegde herinnering die níét in een agenda staat, maar wel
/// hetzelfde wordt behandeld als een agenda-meeting (regels, menu, waarschuwing).
struct CustomReminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var date: Date

    init(id: UUID = UUID(), title: String = "", notes: String = "", date: Date) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
    }
}
