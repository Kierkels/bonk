import SwiftUI

/// De subtiele "Notion Calendar"-achtige pill voor één afspraak/herinnering.
/// Toont icoon + titel + live aftelteller (+ ruimte), met Joinen/Gereed, Snooze
/// (menu) en Sluiten. Klik op de body (icoon/titel) opent het item in de agenda.
struct PillCardView: View {
    let event: UpcomingEvent
    let accent: Color
    var lang: Lang = .nl
    let onJoin: () -> Void
    let onSnooze: (Int) -> Void
    let onSnoozeUntilStart: () -> Void
    let onDismiss: () -> Void
    let onOpenCalendar: () -> Void

    private var isReminder: Bool { event.id.hasPrefix("reminder:") }
    private var hasJoin: Bool { event.joinURL != nil }
    private var canOpenCalendar: Bool { event.calendarItemURL != nil }
    private var icon: String { isReminder ? "bell.fill" : (hasJoin ? "video.fill" : "calendar") }
    private var snoozeUntilStartLabel: String {
        isReminder ? L("Tot het ingestelde tijdstip", "Until the set time", lang)
                   : L("Tot de meeting begint", "Until the meeting starts", lang)
    }
    private var roomText: String? {
        guard let loc = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty else { return nil }
        return loc.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Body (icoon + titel) is klikbaar → open in agenda.
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(accent).font(.system(size: 15))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    subtitle
                }
                .frame(maxWidth: 360, alignment: .leading)   // grens voor extreem lange titels
            }
            .contentShape(Rectangle())
            .onTapGesture { if canOpenCalendar { onOpenCalendar() } }

            // Primaire actie: Joinen (meeting met link) of Gereed (herinnering).
            if hasJoin {
                Button(action: onJoin) {
                    Label(L("Joinen", "Join", lang), systemImage: "video.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.green, in: Capsule())
                }
                .buttonStyle(.plain)
            } else if isReminder {
                Button(action: onDismiss) {
                    Label(L("Gereed", "Done", lang), systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            snoozeMenu
            closeButton
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
    }

    private var subtitle: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 5) {
                Text(pillCountdown(event.start.timeIntervalSince(context.date), lang))
                if let room = roomText {
                    Text("·")
                    Image(systemName: "mappin.and.ellipse")
                    Text(room).lineLimit(1)
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(1)             // nooit naar een tweede regel → geen verticale sprong
        }
    }

    private var snoozeMenu: some View {
        Menu {
            Button(L("1 minuut", "1 minute", lang))   { onSnooze(1) }
            Button(L("2 minuten", "2 minutes", lang)) { onSnooze(2) }
            Button(L("5 minuten", "5 minutes", lang)) { onSnooze(5) }
            Button(L("10 minuten", "10 minutes", lang)) { onSnooze(10) }
            if event.start > Date() {
                Divider()
                Button(snoozeUntilStartLabel) { onSnoozeUntilStart() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "zzz")
                Text(L("Snooze", "Snooze", lang))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
    }
}

/// Korte aftel-tekst voor de pill-subregel.
func pillCountdown(_ seconds: TimeInterval, _ lang: Lang) -> String {
    if seconds <= 0 { return L("begint nu", "starting now", lang) }
    let total = Int(seconds.rounded())
    let m = total / 60
    if m >= 60 { return L("begint over \(m / 60)u \(m % 60)m", "starts in \(m / 60)h \(m % 60)m", lang) }
    if m >= 1 { return L("begint over \(m) min", "starts in \(m) min", lang) }
    return L("begint over \(total) sec", "starts in \(total) sec", lang)
}
