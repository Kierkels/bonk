import SwiftUI
import AppKit

/// Een effen achtergrondlaag die NIET door de vibrancy van het menu-venster
/// halftransparant wordt gemaakt (een SwiftUI `Color` wél). Layer-backed AppKit-
/// view → kleurt exact op de gevraagde dekking, bovenop het systeem-blur.
private struct MenuBackdrop: NSViewRepresentable {
    var opacity: Double

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.backgroundColor = NSColor.windowBackgroundColor
            .withAlphaComponent(opacity).cgColor
    }
}

/// De inhoud van het menubar-popover.
struct MenuView: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject var store: SettingsStore
    @ObservedObject var calendar: CalendarManager
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    private let accent = Color(hex: "#7C3AED")
    private var lang: Lang { store.lang }

    /// Gemeten ideale hoogte van de scrollbare lijst — zodat het venster nog steeds
    /// krimpt bij weinig meetings, maar capt (en scrollt) bij een lange lijst.
    @State private var listContentHeight: CGFloat = 0

    /// Meetings/herinneringen waarvan de kaart is uitgeklapt (toont de beschrijving).
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let version = updates.availableVersion, let url = updates.releaseURL {
                updateBanner(version: version, url: url)
            }

            Divider()

            // Alleen de (variabele) meetinglijst scrollt; header en voettekst (met
            // o.a. Instellingen) blijven altijd zichtbaar — ook bij een lange lijst.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    listContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .frame(height: min(listContentHeight, maxListHeight))
            .onPreferenceChange(ListHeightKey.self) { listContentHeight = $0 }

            Divider()

            footer
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
        // Instelbare dekking: een effen laag bovenop het systeem-blur (layer-backed,
        // dus niet door vibrancy verzwakt). 1 = volledig dekkend; lager laat steeds
        // meer van de doorschijnende achtergrond zien. Ronde vensterhoeken maskeren het.
        .background(MenuBackdrop(opacity: store.settings.menuOpacity).ignoresSafeArea())
        // MenuBarExtra(.window) groeit wel mee maar krimpt niet betrouwbaar als de
        // inhoud kleiner wordt (bv. 3 dagen → alleen vandaag) → te groot/glitcherig
        // venster. `fixedSize` laat de hosting-view z'n ideale hoogte gebruiken, en
        // een `id` die met de lay-outhoogte meeverandert dwingt een rebuild +
        // herberekening van de venstergrootte af.
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(store.colorScheme)
        .id(layoutKey)
    }

    /// Maximale hoogte voor de scrollbare lijst: het zichtbare scherm minus ruimte
    /// voor menubalk, header, voettekst en marges. Daarboven gaat de lijst scrollen.
    private var maxListHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(220, screen - 260)
    }

    /// De variabele inhoud (meetings / lege staat / genegeerd) die mag scrollen.
    @ViewBuilder private var listContent: some View {
        if !calendar.authorized {
            Button {
                Task { await calendar.requestAccess() }
            } label: {
                Label(L("Agendatoegang geven", "Grant calendar access", lang), systemImage: "lock.open")
            }
        } else {
            if !app.upcoming.isEmpty {
                let primary = primaryMeetings
                VStack(alignment: .leading, spacing: 10) {
                    Text(headerText(for: primary))
                        .font(.caption2.weight(.bold)).tracking(0.6)
                        .foregroundStyle(.secondary)
                    ForEach(primary) { nextMeetingCard($0) }
                }
                if !laterMeetings.isEmpty {
                    laterSection
                }
            } else if app.skipped.isEmpty {
                emptyState
            }

            if !app.skipped.isEmpty {
                skippedSection
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Herinneringen toevoegen kan alleen als Bonk aanstaat. Prominente,
            // getinte actieknop — niet zomaar een tekstregel zoals Instellingen/Afsluiten.
            if store.settings.globalEnabled {
                Button {
                    app.openReminderEditor()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.settings.menuBarIcon.symbolName)
                        Text(L("Herinnering toevoegen…", "Add reminder…", lang))
                            .fontWeight(.semibold)
                        if let shortcut = store.settings.quickReminderShortcut {
                            Spacer(minLength: 8)
                            Text(shortcut.displayString)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 11)
                    .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Herinnering toevoegen…", "Add reminder…", lang))
            }

            Button { openSettingsReliably() } label: {
                Label(L("Instellingen…", "Settings…", lang), systemImage: "gearshape")
            }
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label(L("Bonk afsluiten", "Quit Bonk", lang), systemImage: "power")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Verandert zodra de inhoud van hoogte kan wijzigen, zodat het popover-venster
    /// opnieuw wordt opgemeten (zie `.id` hierboven).
    private var layoutKey: String {
        "\(calendar.authorized)|\(app.upcoming.count)|\(app.skipped.count)|\(groupedByDay(laterMeetings).count)|\(updates.availableVersion != nil)|\(expandedIDs.sorted().joined(separator: ","))|\(store.settings.menuCollapsedSections.sorted().joined(separator: ","))"
    }

    // MARK: Onderdelen

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.settings.menuBarIcon.symbolName).foregroundStyle(accent)
            Text("Bonk").font(.headline)
            Spacer()
            // Altijd bereikbaar tandwiel — ook als de meetinglijst lang is.
            Button { openSettingsReliably() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("Instellingen…", "Settings…", lang))
            Toggle("", isOn: $store.settings.globalEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func updateBanner(version: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill").font(.title3)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Update beschikbaar", "Update available", lang))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(L("Versie \(version) — nu downloaden", "Version \(version) — download now", lang))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(L("Open de downloadpagina", "Open the download page", lang))
    }

    private var emptyState: some View {
        let enabled = store.settings.globalEnabled
        let days = store.settings.displayDays
        let window = days == 1
            ? L("alleen vandaag", "today only", lang)
            : L("komende \(days) dagen", "next \(days) days", lang)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(enabled
                     ? L("Geen meetings op komst", "No meetings coming up", lang)
                     : L("Bonk is gepauzeerd", "Bonk is paused", lang))
                    .foregroundStyle(.secondary)
                Text(enabled
                     ? L("Misschien door je filters — weergave (\(window)), agenda's of regels.",
                         "Maybe due to your filters — display (\(window)), calendars or rules.", lang)
                     : L("Toont geen waarschuwingen of meetings tot je Bonk weer aanzet.",
                         "Won't show any alerts or meetings until you switch Bonk back on.", lang))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// Meetings die (vrijwel) tegelijk met de eerstvolgende starten — die horen
    /// allemaal bovenaan als "volgende".
    private var primaryMeetings: [UpcomingEvent] {
        guard let first = app.upcoming.first else { return [] }
        return app.upcoming.filter { abs($0.start.timeIntervalSince(first.start)) < 60 }
    }

    private var laterMeetings: [UpcomingEvent] {
        let ids = Set(primaryMeetings.map { $0.id })
        return app.upcoming.filter { !ids.contains($0.id) }
    }

    private func headerText(for primary: [UpcomingEvent]) -> String {
        if primary.count > 1 { return L("VOLGENDE MEETINGS", "NEXT MEETINGS", lang) }
        if let first = primary.first, first.start <= Date() { return L("NU BEZIG", "IN PROGRESS", lang) }
        return L("VOLGENDE MEETING", "NEXT MEETING", lang)
    }

    private func nextMeetingCard(_ event: UpcomingEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(calendarColor(event.calendarID))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.title).font(.headline).lineLimit(2)
                        if hasDescription(event) {
                            Image(systemName: expandedIDs.contains(event.id) ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(timeRange(event)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if store.settings.showCalendarItemLink, let calURL = event.calendarItemURL {
                    Button {
                        NSWorkspace.shared.open(calURL)
                    } label: {
                        Image(systemName: "calendar")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Open in agenda", "Open in calendar", lang))
                }
                if event.id.hasPrefix("reminder:") {
                    Button {
                        app.editReminder(id: event.id)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Herinnering bewerken", "Edit reminder", lang))
                }
                Button {
                    app.skipMeeting(id: event.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(reminderOrMeetingIgnoreHelp(event))
            }
            .fixedSize(horizontal: false, vertical: true)

            // Live aftelteller (getint: zacht vlak + gekleurde tekst)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = event.start.timeIntervalSince(context.date)
                // Een meeting (met duur) die loopt → "Bezig" (rustig groen). Een
                // momentpunt zoals een herinnering, of iets voorbij z'n tijd → negatief.
                let inProgress = event.end > event.start
                    && context.date >= event.start && context.date < event.end
                let color = inProgress ? .green : urgencyColor(remaining)
                HStack(spacing: 5) {
                    Image(systemName: remaining <= 0 ? "record.circle" : "timer")
                    Text(inProgress ? L("Bezig", "In progress", lang) : countdown(remaining))
                }
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .padding(.vertical, 5).padding(.horizontal, 11)
                .background(color.opacity(0.15), in: Capsule())
            }

            // Ruimte / locatie
            if let room = roomText(event) {
                metaLine(icon: "mappin.and.ellipse", text: room)
            }
            // Agenda + RSVP-status
            if !event.calendarTitle.isEmpty || event.attendance.showsBadge {
                HStack(spacing: 10) {
                    if !event.calendarTitle.isEmpty {
                        metaLine(icon: "calendar", text: event.calendarTitle)
                    }
                    if event.attendance.showsBadge {
                        metaLine(icon: event.attendance.icon, text: event.attendance.label(lang))
                    }
                }
            }

            // Uitgeklapte beschrijving.
            if expandedIDs.contains(event.id), let desc = descriptionText(event) {
                Divider().opacity(0.5)
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let url = event.joinURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(L("Joinen", "Join", lang), systemImage: "video.fill")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        // Hele kaart klikbaar om uit/in te klappen; de knoppen (Joinen, bewerken,
        // sluiten) vangen hun eigen taps en blijven gewoon werken.
        .contentShape(Rectangle())
        .onTapGesture { if hasDescription(event) { toggleExpanded(event.id) } }
    }

    private var laterSection: some View {
        // `upcoming` is al beperkt tot het ingestelde dagvenster + maximum (zie tick).
        // Subtiel gegroepeerd per dag — de dag staat in een kopje, de rijen tonen
        // alleen het tijdstip.
        let groups = groupedByDay(laterMeetings)
        return VStack(alignment: .leading, spacing: 14) {
            sectionHeader(L("DAARNA", "LATER", lang), key: Self.laterSectionKey,
                          count: laterMeetings.count)

            // Elke dag krijgt een eigen kaartje, met het dag-kopje erboven.
            if !isCollapsed(Self.laterSectionKey) {
                ForEach(Array(groups.enumerated()), id: \.element.key) { _, group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(dayHeaderLabel(group.key))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            ForEach(Array(group.events.enumerated()), id: \.element.id) { eventIndex, event in
                                laterRow(event)
                                if eventIndex < group.events.count - 1 {
                                    Divider().opacity(0.4)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func laterRow(_ event: UpcomingEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(event.title).font(.callout).lineLimit(1)
                        if hasDescription(event) {
                            Image(systemName: expandedIDs.contains(event.id) ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 5) {
                        Text(clockTime(event))
                        if let room = roomText(event) {
                            Text("· \(room)").lineLimit(1)
                        }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if event.joinURL != nil {
                    Image(systemName: "video.fill").font(.caption2).foregroundStyle(.secondary)
                }
                if store.settings.showCalendarItemLink, let calURL = event.calendarItemURL {
                    Button {
                        NSWorkspace.shared.open(calURL)
                    } label: {
                        Image(systemName: "calendar").font(.callout).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Open in agenda", "Open in calendar", lang))
                }
                if event.id.hasPrefix("reminder:") {
                    Button {
                        app.editReminder(id: event.id)
                    } label: {
                        Image(systemName: "pencil").font(.callout).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Herinnering bewerken", "Edit reminder", lang))
                }
                Button {
                    app.skipMeeting(id: event.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(reminderOrMeetingIgnoreHelp(event))
            }

            if expandedIDs.contains(event.id), let desc = descriptionText(event) {
                Text(desc)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Agenda-kleurstreepje als leading overlay i.p.v. een greedy HStack-sibling:
        // zo matcht het de rijhoogte en wordt het niet gecomprimeerd bij weinig ruimte.
        .padding(.leading, 13)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(calendarColor(event.calendarID))
                .frame(width: 3)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { if hasDescription(event) { toggleExpanded(event.id) } }
    }

    /// Groepeert (op starttijd gesorteerde) events per kalenderdag, volgorde behouden.
    private func groupedByDay(_ events: [UpcomingEvent]) -> [(key: Date, events: [UpcomingEvent])] {
        let cal = Calendar.current
        var order: [Date] = []
        var map: [Date: [UpcomingEvent]] = [:]
        for e in events {
            let day = cal.startOfDay(for: e.start)
            if map[day] == nil { order.append(day) }
            map[day, default: []].append(e)
        }
        return order.map { (key: $0, events: map[$0] ?? []) }
    }

    /// Subtiel dag-kopje: "Vandaag" / "Morgen" / "Vrijdag 26 jun".
    private func dayHeaderLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return L("Vandaag", "Today", lang) }
        if cal.isDateInTomorrow(date) { return L("Morgen", "Tomorrow", lang) }
        let df = DateFormatter()
        df.locale = Locale(identifier: lang == .en ? "en_US" : "nl_NL")
        df.dateFormat = "EEEE d MMM"
        let s = df.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var skippedSection: some View {
        let items = app.skipped
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader(L("GENEGEERD", "IGNORED", lang), key: Self.skippedSectionKey,
                          count: items.count)

            if !isCollapsed(Self.skippedSectionKey) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                                HStack(spacing: 5) {
                                    Text(shortTime(event))
                                    if let room = roomText(event) { Text("· \(room)").lineLimit(1) }
                                }
                                .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                app.unskipMeeting(id: event.id)
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.body).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L("Weer activeren", "Reactivate", lang))
                        }
                        .padding(.vertical, 7)

                        if index < items.count - 1 {
                            Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Inklapbare secties

    static let laterSectionKey = "later"
    static let skippedSectionKey = "skipped"

    private func isCollapsed(_ key: String) -> Bool {
        store.settings.menuCollapsedSections.contains(key)
    }

    /// Klikbare sectiekop met chevron; ingeklapt toont hij ook het aantal items.
    /// De inklap-status wordt in de instellingen bewaard en overleeft dus herstarts.
    private func sectionHeader(_ title: String, key: String, count: Int) -> some View {
        let collapsed = isCollapsed(key)
        return Button {
            if collapsed { store.settings.menuCollapsedSections.remove(key) }
            else { store.settings.menuCollapsedSections.insert(key) }
        } label: {
            HStack(spacing: 5) {
                Text(collapsed ? "\(title) (\(count))" : title)
                    .font(.caption2.weight(.bold)).tracking(0.6)
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed
              ? L("Sectie uitklappen", "Expand section", lang)
              : L("Sectie inklappen", "Collapse section", lang))
    }

    /// Alleen het tijdstip (de dag staat al in het dag-kopje van de lijst).
    private func clockTime(_ event: UpcomingEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: event.start)
    }

    private func shortTime(_ event: UpcomingEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let cal = Calendar.current
        if cal.isDateInToday(event.start) { return f.string(from: event.start) }
        if cal.isDateInTomorrow(event.start) {
            return L("morgen \(f.string(from: event.start))", "tomorrow \(f.string(from: event.start))", lang)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: lang == .en ? "en_US" : "nl_NL")
        df.dateFormat = "EEE HH:mm"
        return df.string(from: event.start)
    }

    /// De (opgeschoonde) beschrijving van een event, of nil als er geen is.
    private func descriptionText(_ event: UpcomingEvent) -> String? {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else { return nil }
        return notes
    }

    private func hasDescription(_ event: UpcomingEvent) -> Bool {
        descriptionText(event) != nil
    }

    private func toggleExpanded(_ id: String) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
    }

    private func reminderOrMeetingIgnoreHelp(_ event: UpcomingEvent) -> String {
        event.id.hasPrefix("reminder:")
            ? L("Herinnering verwijderen", "Delete reminder", lang)
            : L("Negeren (geen waarschuwing)", "Ignore (no alert)", lang)
    }

    private func metaLine(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).frame(width: 14)
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Helpers

    private func calendarColor(_ id: String) -> Color {
        if let hex = store.settings.calendarColors[id] { return Color(hex: hex) }
        if let cal = calendar.calendars.first(where: { $0.calendarIdentifier == id }) {
            return Color(cal.color)
        }
        return accent
    }

    private func timeRange(_ event: UpcomingEvent) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(event.start) { day = L("Vandaag", "Today", lang) }
        else if cal.isDateInTomorrow(event.start) { day = L("Morgen", "Tomorrow", lang) }
        else {
            let df = DateFormatter()
            df.locale = Locale(identifier: lang == .en ? "en_US" : "nl_NL")
            df.dateFormat = "EEE d MMM"
            day = df.string(from: event.start)
        }
        // Momentpunt (zoals een herinnering): alleen het tijdstip, geen reeks.
        if event.end <= event.start {
            return "\(day) · \(f.string(from: event.start))"
        }
        return "\(day) · \(f.string(from: event.start)) – \(f.string(from: event.end))"
    }

    private func roomText(_ event: UpcomingEvent) -> String? {
        guard let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { return nil }
        return loc.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        // Voorbij de starttijd: negatief doortellen ("al begonnen / X geleden").
        if seconds <= 0 {
            let elapsed = Int((-seconds).rounded())
            let h = elapsed / 3600, m = (elapsed % 3600) / 60, s = elapsed % 60
            if h >= 1 { return L("\(h)u \(m)m geleden", "\(h)h \(m)m ago", lang) }
            if elapsed >= 600 { return L("\(m) min geleden", "\(m) min ago", lang) }
            if m >= 1 { return L("\(m) min \(s) sec geleden", "\(m) min \(s) sec ago", lang) }
            return L("\(s) sec geleden", "\(s) sec ago", lang)
        }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h >= 1 { return L("over \(h)u \(m)m", "in \(h)h \(m)m", lang) }
        if total >= 600 { return L("over \(m) min", "in \(m) min", lang) }
        if m >= 1 { return L("over \(m) min \(s) sec", "in \(m) min \(s) sec", lang) }
        return L("over \(s) sec", "in \(s) sec", lang)
    }

    private func urgencyColor(_ seconds: TimeInterval) -> Color {
        if seconds <= 0 { return .red }        // al begonnen / overtijd
        if seconds <= 120 { return .red }
        if seconds <= 300 { return .orange }
        return .secondary                       // normaal: rustig grijs
    }

    /// Opent de instellingen betrouwbaar vanuit een accessory/menubar-app.
    private func openSettingsReliably() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: {
                    ($0.identifier?.rawValue ?? "").contains("Settings")
                }) {
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                }
            }
        }
    }
}

/// Meet de ideale hoogte van de scrollbare meetinglijst.
private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
