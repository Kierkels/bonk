import Foundation

/// Eén waarschuwingsregel. De eerste passende regel (van boven naar beneden)
/// bepaalt hoe en wanneer er voor een meeting gewaarschuwd wordt.
struct MeetingRule: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "Nieuwe regel"
    var isEnabled: Bool = true
    var titleContains: String = ""        // leeg = elke titel
    var attendanceFilter: Set<Attendance> = []  // leeg = alle; anders alleen deze RSVP-statussen
    var daysOfWeek: Set<Int> = []         // 1=zo ... 7=za ; leeg = alle dagen
    var leadMinutes: Int = 1              // hoeveel minuten van tevoren
    var alertStyle: AlertStyle = .fullScreen
    var autoJoin: Bool = false            // open de link automatisch op starttijd
    var appearanceID: UUID? = nil         // welke weergave-preset (alleen bij schermvullend)
    var calendarIDs: Set<String> = []     // alleen deze agenda's; leeg = alle agenda's
    var notifyWhenLocked: Bool = false    // bij vergrendeld scherm: notificatie + geluid (overlay zie je dan toch niet)
    var notificationSound: String = "default"  // "default" / "none" / NSSound-naam (bv. "Glass")
    var repeatSound: Bool = false         // schermvullend: geluid herhalen (als alarm) tot je reageert
    var soundMaxSeconds: Double = 30      // hoelang het herhalen (alarm) maximaal duurt
    var overrideMute: Bool = false        // geluid ook spelen als de Mac gedempt staat (tijdelijk unmuten)

    func matches(_ event: UpcomingEvent) -> Bool {
        guard isEnabled else { return false }
        if !calendarIDs.isEmpty, !calendarIDs.contains(event.calendarID) { return false }
        let needle = titleContains.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty, !event.title.localizedCaseInsensitiveContains(needle) {
            return false
        }
        if !attendanceFilter.isEmpty, !attendanceFilter.contains(event.attendance) { return false }
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
        // Migratie: oude `onlyAccepted: true` → filter op {accepted}.
        if let set = try c.decodeIfPresent(Set<Attendance>.self, forKey: .attendanceFilter) {
            attendanceFilter = set
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let only = ((try? legacy.decodeIfPresent(Bool.self, forKey: .onlyAccepted)) ?? nil), only {
            attendanceFilter = [.accepted]
        } else {
            attendanceFilter = []
        }
        daysOfWeek = try c.decodeIfPresent(Set<Int>.self, forKey: .daysOfWeek) ?? []
        leadMinutes = try c.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? 1
        alertStyle = try c.decodeIfPresent(AlertStyle.self, forKey: .alertStyle) ?? .fullScreen
        autoJoin = try c.decodeIfPresent(Bool.self, forKey: .autoJoin) ?? false
        appearanceID = try c.decodeIfPresent(UUID.self, forKey: .appearanceID)
        // Migratie: oude regels hadden één `calendarID` → zet om naar een set.
        if let set = try c.decodeIfPresent(Set<String>.self, forKey: .calendarIDs) {
            calendarIDs = set
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let single = ((try? legacy.decodeIfPresent(String.self, forKey: .calendarID)) ?? nil) {
            calendarIDs = [single]
        } else {
            calendarIDs = []
        }
        notifyWhenLocked = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenLocked) ?? false
        notificationSound = try c.decodeIfPresent(String.self, forKey: .notificationSound) ?? "default"
        repeatSound = try c.decodeIfPresent(Bool.self, forKey: .repeatSound) ?? false
        soundMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .soundMaxSeconds) ?? 30
        overrideMute = try c.decodeIfPresent(Bool.self, forKey: .overrideMute) ?? false
    }

    private enum LegacyKeys: String, CodingKey { case calendarID, onlyAccepted }
}
