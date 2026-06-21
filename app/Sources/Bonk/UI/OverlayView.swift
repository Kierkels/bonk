import SwiftUI

/// Het schermvullende scherm: één grote meeting, of meerdere gelijktijdige als kaarten.
struct OverlayContainerView: View {
    let meetings: [OverlayMeeting]
    let background: OverlayAppearance
    var backdrop: NSImage? = nil
    var lang: Lang = .nl
    let onCloseAll: () -> Void

    var body: some View {
        ZStack {
            OverlayBackgroundView(appearance: background, blurImage: backdrop)
                .ignoresSafeArea()

            if meetings.count <= 1 {
                if let meeting = meetings.first {
                    MeetingCardView(meeting: meeting, large: true, lang: lang)
                }
            } else {
                multiView
            }

            // Onzichtbare knop zodat Esc het overlay altijd sluit.
            Button("", action: onCloseAll)
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { onCloseAll() }
    }

    private var multiView: some View {
        VStack(spacing: 30) {
            Spacer()

            VStack(spacing: 10) {
                Text(L("\(meetings.count) meetings", "\(meetings.count) meetings", lang))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let start = meetings.first?.event.start ?? context.date
                    Text(overlayCountdown(start.timeIntervalSince(context.date), lang))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    MeetingRowView(meeting: meeting, lang: lang)
                    if index < meetings.count - 1 {
                        Rectangle().fill(.white.opacity(0.14))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .frame(maxWidth: 620)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 44)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Eén meeting als horizontale rij (gebruikt wanneer er meerdere tegelijk zijn).
struct MeetingRowView: View {
    let meeting: OverlayMeeting
    var lang: Lang = .nl
    private var event: UpcomingEvent { meeting.event }
    private var appearance: OverlayAppearance { meeting.appearance }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1)
                if let meta = metaText {
                    Text(meta)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if event.joinURL != nil {
                    Button(action: meeting.onJoin) {
                        Label(L("Joinen", "Join", lang), systemImage: "video.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .padding(.vertical, 7).padding(.horizontal, 14)
                            .background(Color.green, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Button(L("1 minuut", "1 minute", lang))   { meeting.onSnooze(1) }
                    Button(L("2 minuten", "2 minutes", lang)) { meeting.onSnooze(2) }
                    Button(L("5 minuten", "5 minutes", lang)) { meeting.onSnooze(5) }
                } label: {
                    iconCircle("zzz")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Button(action: meeting.onDismiss) { iconCircle("xmark") }
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14).padding(.horizontal, 18)
    }

    private func iconCircle(_ name: String) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.15))
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
    }

    private var metaText: String? {
        var parts: [String] = []
        if appearance.showTime {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            parts.append(event.end <= event.start
                ? f.string(from: event.start)
                : "\(f.string(from: event.start)) – \(f.string(from: event.end))")
        }
        if appearance.showLocation,
           let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            parts.append(loc.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if appearance.showCalendar, !event.calendarTitle.isEmpty {
            parts.append(event.calendarTitle)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }
}

/// Aftel-tekst gedeeld door de container.
func overlayCountdown(_ seconds: TimeInterval, _ lang: Lang) -> String {
    if seconds <= 0 { return L("Begint nu", "Starting now", lang) }
    let total = Int(seconds.rounded())
    let m = total / 60, s = total % 60
    if m >= 1 { return L("Begint over \(m) min \(s) sec", "Starts in \(m) min \(s) sec", lang) }
    return L("Begint over \(s) sec", "Starts in \(s) sec", lang)
}

/// De inhoud van één meeting. `large` = de solo-weergave (groot, gecentreerd);
/// anders een compacte kaart voor het rooster bij gelijktijdige meetings.
struct MeetingCardView: View {
    let meeting: OverlayMeeting
    var large: Bool
    var lang: Lang = .nl

    private var event: UpcomingEvent { meeting.event }
    private var appearance: OverlayAppearance { meeting.appearance }

    var body: some View {
        VStack(spacing: large ? 24 : 12) {
            if large { Spacer() }

            if appearance.showCountdown { countdownView }

            Text(event.title)
                .font(.system(size: large ? 68 : 24, weight: large ? .heavy : .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(large ? 3 : 2)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, large ? 80 : 8)
                .shadow(color: .black.opacity(0.25), radius: large ? 12 : 6, y: 4)

            if showMeta { metaRow }

            if appearance.showLocation, let room = roomText {
                label(icon: "mappin.and.ellipse", text: room)
                    .font(.system(size: large ? 16 : 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            if appearance.showDescription, let notes = descriptionText {
                Text(notes)
                    .font(.system(size: large ? 16 : 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(large ? 4 : 2)
                    .padding(.horizontal, large ? 120 : 6)
            }

            if large { Spacer() }
            actions
            if large { Spacer().frame(height: 70) }
        }
        .frame(maxWidth: .infinity)
        .padding(large ? 0 : 22)
        .background {
            if !large {
                RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.12))
            }
        }
    }

    // MARK: Onderdelen

    private var countdownView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = event.start.timeIntervalSince(context.date)
            Text(overlayCountdown(remaining, lang))
                .font(.system(size: large ? 26 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .contentTransition(.numericText())
        }
    }

    private var showMeta: Bool {
        appearance.showTime
            || (appearance.showCalendar && !event.calendarTitle.isEmpty)
            || (appearance.showAccepted && event.isAccepted)
    }

    private var metaRow: some View {
        HStack(spacing: large ? 16 : 8) {
            if appearance.showTime {
                label(icon: "clock", text: timeRange)
            }
            if appearance.showCalendar && !event.calendarTitle.isEmpty {
                label(icon: "calendar", text: event.calendarTitle)
            }
            if appearance.showAccepted && event.isAccepted {
                label(icon: "checkmark.circle.fill", text: L("Geaccepteerd", "Accepted", lang))
            }
        }
        .font(.system(size: large ? 16 : 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.85))
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .padding(.vertical, large ? 8 : 5)
        .padding(.horizontal, large ? 14 : 10)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private var actions: some View {
        HStack(spacing: large ? 18 : 10) {
            if event.joinURL != nil {
                Button(action: meeting.onJoin) {
                    actionLabel(L("Joinen", "Join", lang), icon: "video.fill", fill: Color.green)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(large ? KeyboardShortcut(.return, modifiers: []) : nil)
            }

            Menu {
                Button(L("1 minuut", "1 minute", lang))   { meeting.onSnooze(1) }
                Button(L("2 minuten", "2 minutes", lang)) { meeting.onSnooze(2) }
                Button(L("5 minuten", "5 minutes", lang)) { meeting.onSnooze(5) }
            } label: {
                actionLabel(L("Snooze", "Snooze", lang), icon: "zzz", fill: .white.opacity(0.18))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()

            Button(action: meeting.onDismiss) {
                actionLabel(isReminder ? L("Sluiten", "Close", lang) : L("Negeren", "Ignore", lang),
                            icon: "xmark", fill: .white.opacity(0.10))
            }
            .buttonStyle(.plain)
        }
    }

    private var isReminder: Bool { event.id.hasPrefix("reminder:") }

    private func actionLabel(_ title: String, icon: String, fill: some ShapeStyle) -> some View {
        ZStack {
            Capsule().fill(fill)
            Label(title, systemImage: icon)
                .font(.system(size: large ? 20 : 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, large ? 16 : 9)
                .padding(.horizontal, large ? 30 : 16)
        }
        .fixedSize()
    }

    // MARK: Helpers

    private var roomText: String? {
        guard let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { return nil }
        return loc.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }

    private var descriptionText: String? {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return nil }
        return notes
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        if event.end <= event.start { return f.string(from: event.start) }
        return "\(f.string(from: event.start)) – \(f.string(from: event.end))"
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "Begint nu" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        if m >= 1 { return "Begint over \(m) min \(s) sec" }
        return "Begint over \(s) sec"
    }
}
