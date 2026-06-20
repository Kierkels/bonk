import SwiftUI

/// De inhoud van het menubar-popover.
struct MenuView: View {
    @ObservedObject var app: AppDelegate
    @ObservedObject var store: SettingsStore
    @ObservedObject var calendar: CalendarManager
    @Environment(\.openSettings) private var openSettings

    private let accent = Color(hex: "#7C3AED")
    private var lang: Lang { store.lang }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

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

            Divider()

            Button {
                app.openReminderEditor()
            } label: {
                Label(L("Herinnering toevoegen…", "Add reminder…", lang), systemImage: "alarm")
            }

            Button {
                app.testOverlay(appearance: store.settings.appearances.first ?? .default)
            } label: {
                Label(L("Test: 2 meetings (schermvullend)", "Test: 2 meetings (full screen)", lang), systemImage: "rectangle.on.rectangle")
            }

            Button { openSettingsReliably() } label: {
                Label(L("Instellingen…", "Settings…", lang), systemImage: "gearshape")
            }
            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label(L("Bonk afsluiten", "Quit Bonk", lang), systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
        .preferredColorScheme(store.colorScheme)
    }

    // MARK: Onderdelen

    private var header: some View {
        HStack {
            Image(systemName: "bell.badge.fill").foregroundStyle(accent)
            Text("Bonk").font(.headline)
            Spacer()
            Toggle("", isOn: $store.settings.globalEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: store.settings.globalEnabled ? "calendar" : "moon.zzz.fill")
                .font(.title3).foregroundStyle(.secondary)
            Text(store.settings.globalEnabled
                 ? L("Geen meetings op komst", "No meetings coming up", lang)
                 : L("Bonk staat uit", "Bonk is off", lang))
                .foregroundStyle(.secondary)
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
                    Text(event.title).font(.headline).lineLimit(2)
                    Text(timeRange(event)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    app.skipMeeting(id: event.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("Negeren (geen waarschuwing)", "Ignore (no alert)", lang))
            }
            .fixedSize(horizontal: false, vertical: true)

            // Live aftelteller (getint: zacht vlak + gekleurde tekst)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = event.start.timeIntervalSince(context.date)
                let color = urgencyColor(remaining)
                HStack(spacing: 5) {
                    Image(systemName: remaining <= 0 ? "record.circle" : "timer")
                    Text(countdown(remaining))
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
            // Agenda + status
            if !event.calendarTitle.isEmpty || event.isAccepted {
                HStack(spacing: 10) {
                    if !event.calendarTitle.isEmpty {
                        metaLine(icon: "calendar", text: event.calendarTitle)
                    }
                    if event.isAccepted {
                        metaLine(icon: "checkmark.circle.fill", text: L("Geaccepteerd", "Accepted", lang))
                    }
                }
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
    }

    private var laterSection: some View {
        let items = Array(laterMeetings.prefix(4))
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("DAARNA", "LATER", lang))
                .font(.caption2.weight(.bold)).tracking(0.6)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, event in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.callout).lineLimit(1)
                            HStack(spacing: 5) {
                                Text(shortTime(event))
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
                        Button {
                            app.skipMeeting(id: event.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L("Negeren", "Ignore", lang))
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())

                    if index < items.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skippedSection: some View {
        let items = app.skipped
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("GENEGEERD", "IGNORED", lang))
                .font(.caption2.weight(.bold)).tracking(0.6)
                .foregroundStyle(.secondary)

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        if seconds <= 0 { return L("Bezig", "In progress", lang) }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h >= 1 { return L("over \(h)u \(m)m", "in \(h)h \(m)m", lang) }
        if total >= 600 { return L("over \(m) min", "in \(m) min", lang) }
        if m >= 1 { return L("over \(m) min \(s) sec", "in \(m) min \(s) sec", lang) }
        return L("over \(s) sec", "in \(s) sec", lang)
    }

    private func urgencyColor(_ seconds: TimeInterval) -> Color {
        if seconds <= 0 { return .green }      // bezig
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
