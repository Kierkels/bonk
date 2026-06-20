import Foundation

/// Eén waarschuwingsregel. De eerste passende regel (van boven naar beneden)
/// bepaalt hoe en wanneer er voor een meeting gewaarschuwd wordt.
struct MeetingRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Nieuwe regel"
    var isEnabled: Bool = true
    var titleContains: String = ""        // leeg = elke titel
    var onlyAccepted: Bool = false        // alleen meetings die ik heb geaccepteerd
    var daysOfWeek: Set<Int> = []         // 1=zo ... 7=za ; leeg = alle dagen
    var leadMinutes: Int = 1              // hoeveel minuten van tevoren
    var alertStyle: AlertStyle = .fullScreen
    var autoJoin: Bool = false            // open de link automatisch op starttijd
    var appearanceID: UUID? = nil         // welke weergave-preset (alleen bij schermvullend)
    var calendarID: String? = nil         // alleen deze agenda; nil = alle agenda's

    func matches(_ event: UpcomingEvent) -> Bool {
        guard isEnabled else { return false }
        if let calendarID, calendarID != event.calendarID { return false }
        let needle = titleContains.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty, !event.title.localizedCaseInsensitiveContains(needle) {
            return false
        }
        if onlyAccepted, !event.isAccepted { return false }
        if !daysOfWeek.isEmpty, !daysOfWeek.contains(event.weekday) { return false }
        return true
    }
}

extension MeetingRule {
    // Migratie-bestendig: ontbrekende velden (zoals appearanceID in oudere
    // opgeslagen regels) vallen terug op de default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Nieuwe regel"
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        titleContains = try c.decodeIfPresent(String.self, forKey: .titleContains) ?? ""
        onlyAccepted = try c.decodeIfPresent(Bool.self, forKey: .onlyAccepted) ?? false
        daysOfWeek = try c.decodeIfPresent(Set<Int>.self, forKey: .daysOfWeek) ?? []
        leadMinutes = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? 1
        alertStyle = try c.decodeIfPresent(AlertStyle.self, forKey: .alertStyle) ?? .fullScreen
        autoJoin = try c.decodeIfPresent(Bool.self, forKey: .autoJoin) ?? false
        appearanceID = try c.decodeIfPresent(UUID.self, forKey: .appearanceID)
        calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
    }
}
