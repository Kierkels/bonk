import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers
import EventKit

/// Instellingen met een sidebar-indeling à la Pendel: categorieën links,
/// grouped Form-secties rechts.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var calendar: CalendarManager
    var onTest: (OverlayAppearance) -> Void = { _ in }

    @State private var selection: Tab? = .general
    @State private var launchAtLogin = false
    @State private var editingRule: MeetingRule?
    @State private var editingReminder: CustomReminder?

    private var lang: Lang { store.lang }

    enum Tab: String, CaseIterable, Identifiable {
        case general, rules, reminders, appearance, calendars
        var id: String { rawValue }
        func title(_ lang: Lang) -> String {
            switch self {
            case .general:    return L("Algemeen", "General", lang)
            case .rules:      return L("Regels", "Rules", lang)
            case .reminders:  return L("Herinneringen", "Reminders", lang)
            case .appearance: return L("Weergave", "Appearance", lang)
            case .calendars:  return L("Agenda's", "Calendars", lang)
            }
        }
        var icon: String {
            switch self {
            case .general:    return "gearshape"
            case .rules:      return "slider.horizontal.3"
            case .reminders:  return "alarm"
            case .appearance: return "paintbrush"
            case .calendars:  return "calendar"
            }
        }
    }

    // Calendar-weekdagnummers in weekvolgorde: maandag = 2 … zondag = 1.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static func weekdayLabel(_ weekday: Int, _ lang: Lang) -> String {
        let nl = [2: "Ma", 3: "Di", 4: "Wo", 5: "Do", 6: "Vr", 7: "Za", 1: "Zo"]
        let en = [2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat", 1: "Sun"]
        return (lang == .en ? en : nl)[weekday] ?? ""
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selection) { tab in
                Label(tab.title(lang), systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 195, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle((selection ?? .general).title(lang))
        }
        .frame(width: 720, height: 600)
        .onAppear { launchAtLogin = (SMAppService.mainApp.status == .enabled) }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(store: store, calendar: calendar, rule: rule)
        }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorView(store: store, reminder: reminder)
        }
        .preferredColorScheme(store.colorScheme)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .general {
        case .rules:
            rulesTab
        case .reminders:
            remindersTab
        case .appearance:
            AppearanceTab(store: store, onTest: onTest)
        default:
            Form {
                switch selection ?? .general {
                case .general:   generalTab
                case .calendars: calendarsTab
                default:         EmptyView()
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: Algemeen

    @ViewBuilder private var generalTab: some View {
        Section {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 88, height: 88)
                Text(Self.appName).font(.title2.weight(.semibold))
                Text(L("Versie \(Self.appVersion)", "Version \(Self.appVersion)", lang)).font(.caption).foregroundStyle(.secondary)
                Text(Self.copyright).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)

        Section(L("Status", "Status", lang)) {
            Toggle(L("Bonk ingeschakeld", "Bonk enabled", lang), isOn: $store.settings.globalEnabled)
            LabeledContent(L("Agendatoegang", "Calendar access", lang)) {
                if calendar.authorized {
                    Label(L("Verleend", "Granted", lang), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(L("Toegang vragen", "Request access", lang)) { Task { await calendar.requestAccess() } }
                }
            }
        }

        Section {
            Picker(L("Taal", "Language", lang), selection: $store.settings.languageOverride) {
                Text(L("Systeem", "System", lang)).tag("system")
                Text("Nederlands").tag("nl")
                Text("English").tag("en")
            }
            Picker(L("Weergave", "Appearance", lang), selection: $store.settings.appearanceOverride) {
                Text(L("Systeem", "System", lang)).tag("system")
                Text(L("Licht", "Light", lang)).tag("light")
                Text(L("Donker", "Dark", lang)).tag("dark")
            }
        } header: {
            Text(L("Taal & weergave", "Language & appearance", lang))
        }

        Section {
            Picker(L("Menubalk toont", "Menu bar shows", lang), selection: $store.settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.label(lang)).tag($0) }
            }
            Toggle(L("Alleen voor meetings van vandaag", "Only for today's meetings", lang), isOn: $store.settings.menuBarOnlyToday)
        } header: {
            Text(L("Menubalk", "Menu bar", lang))
        } footer: {
            Text(L("Wat er naast het icoon verschijnt voor de eerstvolgende meeting. Met ‘alleen vandaag’ toont de menubalk niets als de meeting niet vandaag is.",
                   "What appears next to the icon for the next meeting. With ‘only today’ the menu bar shows nothing if the meeting isn't today.", lang))
        }

        Section(L("Opstarten", "Startup", lang)) {
            Toggle(L("Starten bij inloggen", "Launch at login", lang), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
        }
    }

    // MARK: Regels

    private var rulesInfoBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            Text(L("Regels worden van boven naar beneden toegepast — de **bovenste** regel die past, wint.",
                   "Rules are applied top to bottom — the **topmost** matching rule wins.", lang))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(12)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.25)))
    }

    private var rulesTab: some View {
        Form {
            rulesInfoBox
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

            Section(L("Waarschuwingsregels", "Alert rules", lang)) {
                ForEach(store.settings.rules) { rule in
                    ruleRow(rule)
                        .contentShape(Rectangle())
                        .onTapGesture { editingRule = rule }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.removeRule(id: rule.id)
                            } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                        }
                }
            }

            Section {
                Button {
                    editingRule = MeetingRule()
                } label: {
                    Label(L("Regel toevoegen", "Add rule", lang), systemImage: "plus")
                }
            } footer: {
                Text(L("Gebruik de ▲▼-knoppen om regels te ordenen.", "Use the ▲▼ buttons to reorder rules.", lang))
            }
        }
        .formStyle(.grouped)
    }

    private func ruleIcon(_ style: AlertStyle) -> String {
        switch style {
        case .fullScreen: return "rectangle.inset.filled"
        case .banner:     return "bell.badge"
        case .ignore:     return "bell.slash"
        }
    }

    private func ruleRow(_ rule: MeetingRule) -> some View {
        let isFirst = store.settings.rules.first?.id == rule.id
        let isLast = store.settings.rules.last?.id == rule.id
        return HStack(spacing: 10) {
            Image(systemName: ruleIcon(rule.alertStyle))
                .font(.title3)
                .foregroundStyle(rule.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.name).fontWeight(.medium)
                    if !rule.isEnabled {
                        Text(L("uit", "off", lang))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.25), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(ruleSummary(rule))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.moveRuleUp(id: rule.id) } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless).disabled(isFirst).help(L("Omhoog", "Move up", lang))

            Button { store.moveRuleDown(id: rule.id) } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless).disabled(isLast).help(L("Omlaag", "Move down", lang))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func calendarName(_ id: String) -> String {
        calendar.calendars.first { $0.calendarIdentifier == id }?.title ?? L("Onbekende agenda", "Unknown calendar", lang)
    }

    private func calendarColorBinding(_ cal: EKCalendar) -> Binding<Color> {
        Binding(
            get: {
                if let hex = store.settings.calendarColors[cal.calendarIdentifier] {
                    return Color(hex: hex)
                }
                return Color(cal.color)
            },
            set: { newColor in
                store.settings.calendarColors[cal.calendarIdentifier] = newColor.hexString
            }
        )
    }

    private func ruleSummary(_ rule: MeetingRule) -> String {
        var parts: [String] = []
        if let calID = rule.calendarID { parts.append(calendarName(calID)) }
        let title = rule.titleContains.trimmingCharacters(in: .whitespaces)
        parts.append(title.isEmpty ? L("Alle titels", "All titles", lang) : L("Titel: “\(title)”", "Title: “\(title)”", lang))
        if rule.onlyAccepted { parts.append(L("Geaccepteerd", "Accepted", lang)) }
        if !rule.daysOfWeek.isEmpty {
            parts.append(Self.weekdayOrder.filter { rule.daysOfWeek.contains($0) }
                .map { Self.weekdayLabel($0, lang) }.joined(separator: " "))
        }
        switch rule.alertStyle {
        case .ignore:
            parts.append(L("negeren", "ignore", lang))
        case .fullScreen:
            parts.append(L("\(rule.leadMinutes) min · schermvullend → \(store.appearanceName(for: rule))",
                           "\(rule.leadMinutes) min · full screen → \(store.appearanceName(for: rule))", lang))
        case .banner:
            parts.append(L("\(rule.leadMinutes) min · notificatie", "\(rule.leadMinutes) min · notification", lang))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Herinneringen

    private var remindersTab: some View {
        Form {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                Text(L("Herinneringen staan níét in je agenda, maar worden net zo behandeld als meetings. Toevoegen kan via het Bonk-menu.",
                       "Reminders aren't in your calendar but are treated like meetings. Add them via the Bonk menu.", lang))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(12)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.25)))
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

            Section {
                if store.settings.reminders.isEmpty {
                    Text(L("Nog geen herinneringen.", "No reminders yet.", lang)).foregroundStyle(.secondary)
                }
                ForEach(store.settings.reminders.sorted { $0.date < $1.date }) { reminder in
                    reminderRow(reminder)
                        .contentShape(Rectangle())
                        .onTapGesture { editingReminder = reminder }
                        .contextMenu {
                            Button(role: .destructive) {
                                store.removeReminder(id: reminder.id)
                            } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                        }
                }
            } header: {
                Text(L("Herinneringen", "Reminders", lang))
            } footer: {
                Text(L("Toevoegen doe je via het Bonk-menu (‘Herinnering toevoegen…’). Klik een herinnering om te bewerken.",
                       "Add via the Bonk menu (‘Add reminder…’). Click a reminder to edit.", lang))
            }
        }
        .formStyle(.grouped)
    }

    private func reminderRow(_ reminder: CustomReminder) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "alarm").font(.title3).foregroundStyle(Color.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title.isEmpty ? L("Herinnering", "Reminder", lang) : reminder.title).fontWeight(.medium)
                Text(reminderDateText(reminder.date)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func reminderDateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return L("Vandaag · \(f.string(from: date))", "Today · \(f.string(from: date))", lang)
    }

    // MARK: Agenda's

    @ViewBuilder private var calendarsTab: some View {
        Section {
            if calendar.calendars.isEmpty {
                Text(L("Geen agendatoegang. Geef toegang via het Algemeen-tabblad.",
                       "No calendar access. Grant it on the General tab.", lang))
                    .foregroundStyle(.secondary)
            }
            ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                HStack {
                    Toggle(isOn: Binding(
                        get: { store.settings.enabledCalendarIDs.contains(cal.calendarIdentifier) },
                        set: { newValue in
                            if newValue { store.settings.enabledCalendarIDs.insert(cal.calendarIdentifier) }
                            else { store.settings.enabledCalendarIDs.remove(cal.calendarIdentifier) }
                        }
                    )) {
                        Text(cal.title)
                    }
                    Spacer()
                    ColorPicker("", selection: calendarColorBinding(cal), supportsOpacity: false)
                        .labelsHidden()
                        .fixedSize()
                }
            }
        } header: {
            Text(L("Welke agenda's volgen?", "Which calendars to follow?", lang))
        } footer: {
            Text(L("Niets aangevinkt = geen agenda-meetings. De kleur bepaalt de markering in het menu.",
                   "Nothing checked = no calendar meetings. The colour sets the marker in the menu.", lang))
        }
    }

    // MARK: Acties / helpers

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (build \(build))"
    }
    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Bonk"
    }
    static var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 Roland Kierkels"
    }
}

// MARK: - Weergave-tab (lijst van presets)

private struct AppearanceTab: View {
    @ObservedObject var store: SettingsStore
    var onTest: (OverlayAppearance) -> Void
    @State private var editing: OverlayAppearance?
    private var lang: Lang { store.lang }

    var body: some View {
        Form {
            Section(L("Weergaven", "Appearances", lang)) {
                ForEach(store.settings.appearances) { appearance in
                    Button { editing = appearance } label: { row(appearance) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if store.settings.appearances.count > 1 {
                                Button(role: .destructive) {
                                    store.removeAppearance(id: appearance.id)
                                } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                            }
                        }
                }
            }

            Section {
                Button {
                    editing = OverlayAppearance(name: L("Nieuwe weergave", "New appearance", lang))
                } label: {
                    Label(L("Weergave toevoegen", "Add appearance", lang), systemImage: "plus")
                }
            } footer: {
                Text(L("Maak meerdere weergaven en kies er per schermvullende regel één — bijv. een rustige blur voor 1-op-1's en een felle gradient voor all-hands.",
                       "Create multiple appearances and pick one per full-screen rule — e.g. a calm blur for 1-on-1s and a bold gradient for all-hands.", lang))
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { appearance in
            AppearanceEditorView(store: store, appearance: appearance, onTest: onTest)
        }
    }

    private func row(_ appearance: OverlayAppearance) -> some View {
        HStack(spacing: 12) {
            OverlayBackgroundView(appearance: appearance, animated: false)
                .frame(width: 48, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            VStack(alignment: .leading, spacing: 2) {
                Text(appearance.name).fontWeight(.medium)
                Text(appearance.styleSummary(store.lang)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - Weergave-editor (sheet)

private struct AppearanceEditorView: View {
    @ObservedObject var store: SettingsStore
    var onTest: (OverlayAppearance) -> Void
    @State private var draft: OverlayAppearance
    @State private var previewShot: NSImage?
    @State private var showImporter = false
    @State private var permissionAsked = false
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore, appearance: OverlayAppearance, onTest: @escaping (OverlayAppearance) -> Void) {
        self.store = store
        self.onTest = onTest
        _draft = State(initialValue: appearance)
    }

    private var lang: Lang { store.lang }
    private var isExisting: Bool { store.settings.appearances.contains { $0.id == draft.id } }
    private var canDelete: Bool { isExisting && store.settings.appearances.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    OverlayPreview(appearance: draft, blurImage: previewShot, lang: lang)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .listRowInsets(EdgeInsets())
                    Button {
                        onTest(draft)
                    } label: {
                        Label(L("Test op volledig scherm", "Test full screen", lang), systemImage: "play.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                }

                Section(L("Naam", "Name", lang)) {
                    TextField(L("Naam", "Name", lang), text: $draft.name).labelsHidden().textFieldStyle(.roundedBorder)
                }

                Section(L("Achtergrond", "Background", lang)) {
                    Picker(L("Stijl", "Style", lang), selection: $draft.style) {
                        ForEach(OverlayBackgroundStyle.allCases) { Text($0.label(store.lang)).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch draft.style {
                    case .gradient, .solid:
                        ColorPicker(L("Kleur", "Colour", lang), selection: Binding(
                            get: { Color(hex: draft.accentHex) },
                            set: { draft.accentHex = $0.hexString }
                        ), supportsOpacity: false)
                    case .blur:
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(L("Blur-sterkte", "Blur strength", lang), value: "\(Int(draft.blurRadius))")
                            Slider(value: $draft.blurRadius, in: 0...60)
                            if ScreenCapture.hasAccess {
                                Text(L("Legt je scherm vast en blurt het met deze sterkte.",
                                       "Captures your screen and blurs it at this strength.", lang))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(L("Zonder schermopname-toegang gebruikt Bonk een vaste frosted-glass blur (de sterkte heeft dan geen effect).",
                                       "Without screen-recording access Bonk uses a fixed frosted-glass blur (strength has no effect).", lang))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(L("Schermopname-toegang geven", "Grant screen-recording access", lang)) {
                                    ScreenCapture.requestAccess()
                                    permissionAsked = true
                                }
                                if permissionAsked {
                                    Label(L("Vink Bonk aan in Systeeminstellingen › Privacy › Schermopname en herstart Bonk.",
                                            "Tick Bonk in System Settings › Privacy › Screen Recording and restart Bonk.", lang),
                                          systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    case .image:
                        HStack {
                            Button(L("Kies afbeelding…", "Choose image…", lang)) { showImporter = true }
                            Spacer()
                            if let path = draft.imagePath {
                                Text((path as NSString).lastPathComponent)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Button { draft.imagePath = nil } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).help(L("Wissen", "Clear", lang))
                            } else {
                                Text(L("Geen afbeelding", "No image", lang)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(L("Verdonkeren", "Darken", lang), value: "\(Int(draft.scrim * 100))%")
                        Slider(value: $draft.scrim, in: 0...0.8)
                    }
                } header: {
                    Text(L("Leesbaarheid", "Readability", lang))
                }

                Section {
                    Toggle(L("Aftelklok", "Countdown", lang), isOn: $draft.showCountdown)
                    Toggle(L("Tijd", "Time", lang), isOn: $draft.showTime)
                    Toggle(L("Agenda", "Calendar", lang), isOn: $draft.showCalendar)
                    Toggle(L("Geaccepteerd-status", "Accepted status", lang), isOn: $draft.showAccepted)
                    Toggle(L("Ruimte / locatie", "Room / location", lang), isOn: $draft.showLocation)
                    Toggle(L("Beschrijving", "Description", lang), isOn: $draft.showDescription)
                } header: {
                    Text(L("Tonen op het scherm", "Show on screen", lang))
                } footer: {
                    Text(L("De titel van de meeting wordt altijd getoond.", "The meeting title is always shown.", lang))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if canDelete {
                    Button(role: .destructive) {
                        store.removeAppearance(id: draft.id); dismiss()
                    } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                }
                Spacer()
                Button(L("Annuleer", "Cancel", lang)) { dismiss() }
                Button(L("Bewaar", "Save", lang)) { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 660)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first {
                draft.imagePath = url.path
            }
        }
        .task(id: draft.style) {
            if draft.style == .blur, previewShot == nil {
                previewShot = await ScreenCapture.capture(displayID: ScreenCapture.mainDisplayID())
            }
        }
    }

    private func save() {
        if isExisting { store.updateAppearance(draft) } else { store.addAppearance(draft) }
    }
}

/// Verkleinde, niet-geanimeerde weergave van de overlay-achtergrond met voorbeeldtekst.
private struct OverlayPreview: View {
    let appearance: OverlayAppearance
    var blurImage: NSImage? = nil
    var lang: Lang = .nl

    var body: some View {
        ZStack {
            OverlayBackgroundView(appearance: appearance, animated: false, blurImage: blurImage)
            VStack(spacing: 6) {
                Text(L("Begint over 1 min", "Starts in 1 min", lang)).font(.caption2).foregroundStyle(.white.opacity(0.85))
                Text("Sprint Review")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Regel-editor (sheet)

private struct RuleEditorView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var calendar: CalendarManager
    @State private var draft: MeetingRule
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore, calendar: CalendarManager, rule: MeetingRule) {
        self.store = store
        self.calendar = calendar
        _draft = State(initialValue: rule)
    }

    private var lang: Lang { store.lang }
    private var isExisting: Bool { store.settings.rules.contains { $0.id == draft.id } }

    private var appearanceBinding: Binding<UUID?> {
        Binding(
            get: { draft.appearanceID ?? store.settings.appearances.first?.id },
            set: { draft.appearanceID = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L("Regel", "Rule", lang)) {
                    field(L("Naam", "Name", lang)) {
                        TextField(L("Naam", "Name", lang), text: $draft.name).labelsHidden().textFieldStyle(.roundedBorder)
                    }
                    Toggle(L("Ingeschakeld", "Enabled", lang), isOn: $draft.isEnabled)
                }

                Section {
                    Picker(L("Actie", "Action", lang), selection: $draft.alertStyle) {
                        ForEach(AlertStyle.allCases) { Text($0.label(store.lang)).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if draft.alertStyle != .ignore {
                        Stepper(value: $draft.leadMinutes, in: 0...60) {
                            Text(L("Waarschuw \(draft.leadMinutes) min van tevoren", "Alert \(draft.leadMinutes) min before", lang))
                        }
                        if draft.alertStyle == .fullScreen {
                            Picker(L("Weergave", "Appearance", lang), selection: appearanceBinding) {
                                ForEach(store.settings.appearances) { appearance in
                                    Text(appearance.name).tag(Optional(appearance.id))
                                }
                            }
                        }
                        Toggle(L("Automatisch joinen op starttijd", "Auto-join at start time", lang), isOn: $draft.autoJoin)
                    }
                } header: {
                    Text(L("Actie", "Action", lang))
                } footer: {
                    if draft.alertStyle == .ignore {
                        Text(L("Meetings die op deze regel passen worden automatisch genegeerd (geen waarschuwing).",
                               "Meetings matching this rule are automatically ignored (no alert).", lang))
                    }
                }

                Section {
                    Picker(L("Agenda", "Calendar", lang), selection: $draft.calendarID) {
                        Text(L("Alle agenda's", "All calendars", lang)).tag(String?.none)
                        ForEach(calendar.calendars, id: \.calendarIdentifier) { cal in
                            Text(cal.title).tag(Optional(cal.calendarIdentifier))
                        }
                    }
                    field(L("Titel bevat (leeg = elke titel)", "Title contains (empty = any title)", lang)) {
                        TextField(L("(elke titel)", "(any title)", lang), text: $draft.titleContains)
                            .labelsHidden().textFieldStyle(.roundedBorder)
                    }
                    Toggle(L("Alleen geaccepteerde meetings", "Only accepted meetings", lang), isOn: $draft.onlyAccepted)
                    field(L("Op deze dagen (leeg = elke dag)", "On these days (empty = every day)", lang)) {
                        HStack(spacing: 4) {
                            ForEach(SettingsView.weekdayOrder, id: \.self) { weekday in
                                DayChip(label: SettingsView.weekdayLabel(weekday, store.lang),
                                        selected: draft.daysOfWeek.contains(weekday)) {
                                    if draft.daysOfWeek.contains(weekday) { draft.daysOfWeek.remove(weekday) }
                                    else { draft.daysOfWeek.insert(weekday) }
                                }
                            }
                        }
                    }
                } header: {
                    Text(L("Filter", "Filter", lang))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isExisting {
                    Button(role: .destructive) {
                        store.removeRule(id: draft.id); dismiss()
                    } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                }
                Spacer()
                Button(L("Annuleer", "Cancel", lang)) { dismiss() }
                Button(L("Bewaar", "Save", lang)) { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 560)
    }

    private func save() {
        if isExisting { store.updateRule(draft) } else { store.addRule(draft) }
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Herbruikbare componenten

/// Een kleine schakelbare dag-knop (Ma, Di, …).
struct ReminderEditorView: View {
    @ObservedObject var store: SettingsStore
    var onClose: (() -> Void)? = nil
    @State private var draft: CustomReminder
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore, reminder: CustomReminder, onClose: (() -> Void)? = nil) {
        self.store = store
        self.onClose = onClose
        _draft = State(initialValue: reminder)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var lang: Lang { store.lang }
    private var isExisting: Bool { store.settings.reminders.contains { $0.id == draft.id } }
    private var canSave: Bool { !draft.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(L("Herinnering", "Reminder", lang)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Titel", "Title", lang)).font(.caption).foregroundStyle(.secondary)
                        TextField(L("Titel", "Title", lang), text: $draft.title).labelsHidden().textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Beschrijving (optioneel)", "Description (optional)", lang)).font(.caption).foregroundStyle(.secondary)
                        TextField(L("Beschrijving", "Description", lang), text: $draft.notes).labelsHidden().textFieldStyle(.roundedBorder)
                    }
                }
                Section {
                    DatePicker(L("Tijd", "Time", lang), selection: $draft.date,
                               displayedComponents: [.hourAndMinute])
                } header: {
                    Text(L("Wanneer", "When", lang))
                } footer: {
                    Text(L("Herinneringen gelden voor vandaag.", "Reminders apply to today.", lang))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if isExisting {
                    Button(role: .destructive) {
                        store.removeReminder(id: draft.id); close()
                    } label: { Label(L("Verwijderen", "Delete", lang), systemImage: "trash") }
                }
                Spacer()
                Button(L("Annuleer", "Cancel", lang)) { close() }
                Button(L("Bewaar", "Save", lang)) { save(); close() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 460, height: 380)
        .preferredColorScheme(store.colorScheme)
    }

    private func save() {
        if isExisting { store.updateReminder(draft) } else { store.addReminder(draft) }
    }
}

private struct DayChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 30, height: 26)
                .background(
                    selected ? Color.accentColor : Color.secondary.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
