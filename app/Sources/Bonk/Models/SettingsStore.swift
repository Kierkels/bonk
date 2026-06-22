import Foundation
import Combine
import SwiftUI

/// Wat Bonk in de menubalk toont naast/in plaats van het icoon.
enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case icon
    case countdown
    case titleCountdown
    case titleTime
    case time

    var id: String { rawValue }
    func label(_ lang: Lang) -> String {
        switch self {
        case .icon:           return L("Alleen icoon", "Icon only", lang)
        case .countdown:      return L("Aftelteller", "Countdown", lang)
        case .titleCountdown: return L("Titel + aftelteller", "Title + countdown", lang)
        case .titleTime:      return L("Titel + tijdstip", "Title + time", lang)
        case .time:           return L("Tijdstip", "Time", lang)
        }
    }
}

struct AppSettings: Codable {
    var rules: [MeetingRule]
    var enabledCalendarIDs: Set<String>   // leeg = alle agenda's
    var globalEnabled: Bool
    var appearances: [OverlayAppearance]  // herbruikbare weergave-presets
    var menuBarStyle: MenuBarStyle = .countdown
    var displayDays: Int = 1              // hoeveel dagen het menu toont; 1 = alleen vandaag
    var maxMeetings: Int? = nil           // optioneel maximum aantal agenda-meetings (nil = alle)
    var menuBarOnlyToday: Bool = false    // menubalk-tekst alleen tonen als de eerstvolgende meeting vandaag is
    var menuBarHighlightEnabled: Bool = false      // gekleurde achtergrond als meeting nabij is
    var menuBarHighlightMinutes: Int = 5           // "nabij" = binnen zoveel minuten
    var menuBarHighlightColorMode: String = "calendar"  // calendar | custom
    var menuBarHighlightColorHex: String = "#E72677"    // eigen kleur (mode = custom)
    var reminders: [CustomReminder] = []  // zelf toegevoegde herinneringen
    // Globale weergave van herinneringen (los van de meeting-regels; geldt voor álle herinneringen).
    var reminderAlertStyle: AlertStyle = .fullScreen
    var reminderLeadMinutes: Int = 0
    var reminderAppearanceID: UUID? = nil
    var reminderSound: String = "default"
    var reminderNotifyWhenLocked: Bool = false
    var reminderRepeatSound: Bool = false
    var reminderSoundMaxSeconds: Double = 30
    var reminderOverrideMute: Bool = false
    var calendarColors: [String: String] = [:]   // calendarID → hex-kleur in het menu
    var calendarsMigrated: Bool = false           // eenmalige migratie naar "leeg = geen"
    var languageOverride: String = "system"       // system / nl / en
    var appearanceOverride: String = "system"     // system / light / dark

    static let `default` = AppSettings(
        rules: [
            MeetingRule(
                name: "Alle meetings",
                isEnabled: true,
                titleContains: "",
                daysOfWeek: [],
                leadMinutes: 1,
                alertStyle: .fullScreen,
                autoJoin: false
            )
        ],
        enabledCalendarIDs: [],
        globalEnabled: true,
        appearances: [OverlayAppearance(name: "Standaard")]
    )

    init(rules: [MeetingRule],
         enabledCalendarIDs: Set<String>,
         globalEnabled: Bool,
         appearances: [OverlayAppearance],
         menuBarStyle: MenuBarStyle = .countdown) {
        self.rules = rules
        self.enabledCalendarIDs = enabledCalendarIDs
        self.globalEnabled = globalEnabled
        self.appearances = appearances
        self.menuBarStyle = menuBarStyle
    }

    enum CodingKeys: String, CodingKey {
        case rules, enabledCalendarIDs, globalEnabled, appearances, menuBarStyle, displayDays, maxMeetings, menuBarOnlyToday, reminders, calendarColors, calendarsMigrated, languageOverride, appearanceOverride
        case menuBarHighlightEnabled, menuBarHighlightMinutes, menuBarHighlightColorMode, menuBarHighlightColorHex
        case reminderAlertStyle, reminderLeadMinutes, reminderAppearanceID, reminderSound, reminderNotifyWhenLocked, reminderRepeatSound, reminderSoundMaxSeconds, reminderOverrideMute
    }
    private enum LegacyKeys: String, CodingKey {
        case overlayAppearance
    }

    // Migratie-bestendig: oude instellingen met één `overlayAppearance` worden
    // omgezet naar een lijst met één preset.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([MeetingRule].self, forKey: .rules) ?? AppSettings.default.rules
        enabledCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .enabledCalendarIDs) ?? []
        globalEnabled = try c.decodeIfPresent(Bool.self, forKey: .globalEnabled) ?? true
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? .countdown
        displayDays = try c.decodeIfPresent(Int.self, forKey: .displayDays) ?? 1
        maxMeetings = try c.decodeIfPresent(Int.self, forKey: .maxMeetings)
        menuBarOnlyToday = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnlyToday) ?? false
        menuBarHighlightEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarHighlightEnabled) ?? false
        menuBarHighlightMinutes = try c.decodeIfPresent(Int.self, forKey: .menuBarHighlightMinutes) ?? 5
        menuBarHighlightColorMode = try c.decodeIfPresent(String.self, forKey: .menuBarHighlightColorMode) ?? "calendar"
        menuBarHighlightColorHex = try c.decodeIfPresent(String.self, forKey: .menuBarHighlightColorHex) ?? "#E72677"
        reminders = try c.decodeIfPresent([CustomReminder].self, forKey: .reminders) ?? []
        reminderAlertStyle = try c.decodeIfPresent(AlertStyle.self, forKey: .reminderAlertStyle) ?? .fullScreen
        reminderLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderLeadMinutes) ?? 0
        reminderAppearanceID = try c.decodeIfPresent(UUID.self, forKey: .reminderAppearanceID)
        reminderSound = try c.decodeIfPresent(String.self, forKey: .reminderSound) ?? "default"
        reminderNotifyWhenLocked = try c.decodeIfPresent(Bool.self, forKey: .reminderNotifyWhenLocked) ?? false
        reminderRepeatSound = try c.decodeIfPresent(Bool.self, forKey: .reminderRepeatSound) ?? false
        reminderSoundMaxSeconds = try c.decodeIfPresent(Double.self, forKey: .reminderSoundMaxSeconds) ?? 30
        reminderOverrideMute = try c.decodeIfPresent(Bool.self, forKey: .reminderOverrideMute) ?? false
        calendarColors = try c.decodeIfPresent([String: String].self, forKey: .calendarColors) ?? [:]
        calendarsMigrated = try c.decodeIfPresent(Bool.self, forKey: .calendarsMigrated) ?? false
        languageOverride = try c.decodeIfPresent(String.self, forKey: .languageOverride) ?? "system"
        appearanceOverride = try c.decodeIfPresent(String.self, forKey: .appearanceOverride) ?? "system"

        if let arr = try c.decodeIfPresent([OverlayAppearance].self, forKey: .appearances), !arr.isEmpty {
            appearances = arr
        } else if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
                  let single = ((try? legacy.decodeIfPresent(OverlayAppearance.self, forKey: .overlayAppearance)) ?? nil) {
            appearances = [single]
        } else {
            appearances = AppSettings.default.appearances
        }
    }
}

/// Bewaart instellingen in UserDefaults en publiceert wijzigingen naar de UI.
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings { didSet { save() } }
    private let key = "BonkSettings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    /// Actieve taal (override of systeem; standaard Engels buiten NL).
    var lang: Lang {
        switch settings.languageOverride {
        case "nl": return .nl
        case "en": return .en
        default:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return code == "nl" ? .nl : .en
        }
    }

    /// Geforceerd kleurschema, of nil voor systeem.
    var colorScheme: ColorScheme? {
        switch settings.appearanceOverride {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// De eerste regel die op deze afspraak past (volgorde-gebaseerd).
    func rule(for event: UpcomingEvent) -> MeetingRule? {
        settings.rules.first { $0.matches(event) }
    }

    /// De eerste passende waarschuwende regel (geen negeer-regel) — voor events
    /// die expliciet weer geactiveerd zijn.
    func firstAlertRule(for event: UpcomingEvent) -> MeetingRule? {
        settings.rules.first { $0.alertStyle != .ignore && $0.matches(event) }
    }

    func moveRuleUp(id: UUID) {
        guard let i = settings.rules.firstIndex(where: { $0.id == id }), i > 0 else { return }
        settings.rules.swapAt(i, i - 1)
    }

    func moveRuleDown(id: UUID) {
        guard let i = settings.rules.firstIndex(where: { $0.id == id }), i < settings.rules.count - 1 else { return }
        settings.rules.swapAt(i, i + 1)
    }

    // MARK: Herinneringen beheren

    func addReminder(_ reminder: CustomReminder) {
        settings.reminders.append(reminder)
    }

    func updateReminder(_ reminder: CustomReminder) {
        if let i = settings.reminders.firstIndex(where: { $0.id == reminder.id }) {
            settings.reminders[i] = reminder
        }
    }

    func removeReminder(id: UUID) {
        settings.reminders.removeAll { $0.id == id }
    }

    // MARK: Regels beheren

    func addRule(_ rule: MeetingRule) {
        settings.rules.append(rule)
    }

    func updateRule(_ rule: MeetingRule) {
        if let i = settings.rules.firstIndex(where: { $0.id == rule.id }) {
            settings.rules[i] = rule
        }
    }

    func removeRule(id: UUID) {
        settings.rules.removeAll { $0.id == id }
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        settings.rules.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: Weergaven beheren

    /// De weergave-preset die bij een regel hoort (valt terug op de eerste).
    func appearance(for rule: MeetingRule) -> OverlayAppearance {
        if let id = rule.appearanceID, let match = settings.appearances.first(where: { $0.id == id }) {
            return match
        }
        return settings.appearances.first ?? .default
    }

    func addAppearance(_ appearance: OverlayAppearance) {
        settings.appearances.append(appearance)
    }

    func updateAppearance(_ appearance: OverlayAppearance) {
        if let i = settings.appearances.firstIndex(where: { $0.id == appearance.id }) {
            settings.appearances[i] = appearance
        }
    }

    func removeAppearance(id: UUID) {
        guard settings.appearances.count > 1 else { return }   // minstens één behouden
        settings.appearances.removeAll { $0.id == id }
        // regels die naar deze weergave verwezen vallen terug op de standaard
        for i in settings.rules.indices where settings.rules[i].appearanceID == id {
            settings.rules[i].appearanceID = nil
        }
    }

    /// Naam van de weergave die een regel gebruikt (voor in samenvattingen).
    func appearanceName(for rule: MeetingRule) -> String {
        appearance(for: rule).name
    }
}
