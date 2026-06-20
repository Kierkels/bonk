import AppKit
import SwiftUI
import UserNotifications
import EventKit
import Combine

/// Coördineert alles: agenda pollen, regels matchen en alerts afvuren.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    let settingsStore = SettingsStore()
    let calendar = CalendarManager()
    private let overlay = OverlayController()

    @Published var nextEvent: UpcomingEvent?
    @Published var upcoming: [UpcomingEvent] = []
    @Published var skipped: [UpcomingEvent] = []

    private var timer: Timer?
    private var firedKeys: Set<String> = []
    private var snoozeUntil: [String: Date] = [:]
    private var dismissedIDs: Set<String> = []      // handmatig genegeerd
    private var forceShownIDs: Set<String> = []     // weer geactiveerd (overschrijft negeer-regel)
    private var cancellables = Set<AnyCancellable>()
    private let dismissedKey = "BonkDismissedIDs.v1"
    private let forceShownKey = "BonkForceShownIDs.v1"

    /// Wordt deze meeting genegeerd? Volgorde-gebaseerd: handmatig negeren of de
    /// eerste passende regel is een negeer-regel — tenzij expliciet weer geactiveerd.
    private func isIgnored(_ event: UpcomingEvent) -> Bool {
        if forceShownIDs.contains(event.id) { return false }
        if dismissedIDs.contains(event.id) { return true }
        return settingsStore.rule(for: event)?.alertStyle == .ignore
    }

    /// De regel die bepaalt hoe gewaarschuwd wordt (nil = niet waarschuwen).
    private func warnRule(for event: UpcomingEvent) -> MeetingRule? {
        guard !isIgnored(event) else { return nil }
        return settingsStore.firstAlertRule(for: event)
    }

    /// Tekst voor in de menubalk, afhankelijk van de gekozen stijl.
    var menuBarText: String? {
        let style = settingsStore.settings.menuBarStyle
        guard style != .icon, let n = nextEvent else { return nil }
        if settingsStore.settings.menuBarOnlyToday,
           !Calendar.current.isDateInToday(n.start) { return nil }

        let cd = shortCountdown(n.start.timeIntervalSinceNow)
        let time = menuBarTime(n.start)

        // Meerdere meetings tegelijk → toon aantal i.p.v. één titel.
        let simultaneous = upcoming.filter { abs($0.start.timeIntervalSince(n.start)) < 60 }.count
        let titlePart = simultaneous > 1 ? "\(simultaneous) meetings" : truncatedTitle(n.title)

        switch style {
        case .icon:           return nil
        case .countdown:      return cd
        case .titleCountdown: return "\(titlePart), \(cd)"
        case .titleTime:      return "\(titlePart), \(time)"
        case .time:           return time
        }
    }

    private func truncatedTitle(_ title: String, max: Int = 24) -> String {
        title.count > max ? String(title.prefix(max - 1)) + "…" : title
    }

    private func shortCountdown(_ seconds: TimeInterval) -> String {
        let lang = settingsStore.lang
        if seconds <= 0 { return L("bezig", "now", lang) }
        if seconds < 60 { return L("nu", "now", lang) }
        let m = Int((seconds / 60).rounded(.down))
        if m >= 1440 { return L("in \(m / 1440)d", "in \(m / 1440)d", lang) }
        if m >= 60 { return L("in \(m / 60)u", "in \(m / 60)h", lang) }
        return L("in \(m)m", "in \(m)m", lang)
    }

    private func menuBarTime(_ date: Date) -> String {
        let lang = settingsStore.lang
        let f = DateFormatter()
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if cal.isDateInTomorrow(date) {
            f.dateFormat = "HH:mm"
            return L("morgen \(f.string(from: date))", "tomorrow \(f.string(from: date))", lang)
        }
        f.locale = Locale(identifier: lang == .en ? "en_US" : "nl_NL")
        f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        dismissedIDs = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
        forceShownIDs = Set(UserDefaults.standard.stringArray(forKey: forceShownKey) ?? [])
        UNUserNotificationCenter.current().delegate = self
        BannerNotifier.requestAuth(lang: settingsStore.lang)
        Task {
            await calendar.requestAccess()
            startTimer()
            observeCalendarChanges()
            observeSettings()
            tick()
            handleLaunchFlags()
        }
    }

    /// Hulp voor het maken van screenshots: `--open-settings` / `--overlay`.
    private func handleLaunchFlags() {
        let args = CommandLine.arguments
        if args.contains("--overlay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.testOverlay(appearance: self.settingsStore.settings.appearances.first ?? .default)
            }
        }
        if args.contains("--overlay1") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                let demo = UpcomingEvent(
                    id: "demo", title: "Sprint Review",
                    start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(1860),
                    calendarTitle: "Q42", calendarID: "demo", isAccepted: true,
                    joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                    location: "AMS-1-02 - The Marble Room (8)",
                    notes: "Even syncen over de planning voor volgende sprint.",
                    weekday: 2
                )
                self.overlay.show(
                    event: demo,
                    rule: self.settingsStore.settings.rules.first ?? MeetingRule(),
                    appearance: self.settingsStore.settings.appearances.first ?? .default,
                    lang: self.settingsStore.lang,
                    onJoin: {}, onSnooze: { _ in }, onDismiss: {}
                )
            }
        }
        if args.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                let view = SettingsView(store: self.settingsStore, calendar: self.calendar, onTest: { _ in })
                let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
                win.title = "Bonk"
                win.contentView = NSHostingView(rootView: view)
                win.isReleasedWhenClosed = false
                win.center()
                self.shotWindow = win
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Herbereken de lijst zodra instellingen (zoals regels) wijzigen.
    private func observeSettings() {
        settingsStore.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.tick() }
            }
            .store(in: &cancellables)
    }

    /// Reageer direct op agenda-wijzigingen (toevoegen/wijzigen/sync) i.p.v. te
    /// wachten op de volgende timer-tick.
    private func observeCalendarChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: calendar.store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Eenmalig: oude "leeg = alle agenda's" omzetten naar expliciet alle agenda's,
    /// zodat "leeg = geen" voortaan klopt zonder de huidige selectie te verliezen.
    private func migrateCalendarsIfNeeded() {
        guard !settingsStore.settings.calendarsMigrated, !calendar.calendars.isEmpty else { return }
        if settingsStore.settings.enabledCalendarIDs.isEmpty {
            settingsStore.settings.enabledCalendarIDs = Set(calendar.calendars.map { $0.calendarIdentifier })
        }
        settingsStore.settings.calendarsMigrated = true
    }

    func tick() {
        migrateCalendarsIfNeeded()
        guard settingsStore.settings.globalEnabled else {
            nextEvent = nil
            upcoming = []
            skipped = []
            return
        }
        let now = Date()

        // Herinneringen gelden alleen voor vandaag — ruim oudere op.
        let startOfToday = Calendar.current.startOfDay(for: now)
        let liveReminders = settingsStore.settings.reminders.filter { $0.date >= startOfToday }
        if liveReminders.count != settingsStore.settings.reminders.count {
            settingsStore.settings.reminders = liveReminders
        }

        let events = (calendar.upcomingEvents(
            within: 48,
            enabledCalendarIDs: settingsStore.settings.enabledCalendarIDs
        ) + reminderEvents(now: now))
            .sorted { $0.start < $1.start }

        // Opgeslagen keuzes opschonen zodra meetings uit het venster vallen.
        let ids = Set(events.map { $0.id })
        let before = (dismissedIDs.count, forceShownIDs.count)
        dismissedIDs.formIntersection(ids)
        forceShownIDs.formIntersection(ids)
        if (dismissedIDs.count, forceShownIDs.count) != before { saveChoices() }

        // Toon de meetings waar een waarschuwende regel op past; genegeerde apart.
        upcoming = events.filter { $0.end > now && warnRule(for: $0) != nil }
        nextEvent = upcoming.first
        skipped = events.filter { $0.end > now && isIgnored($0) }

        writeDiagnostics(events, now: now)

        for event in events {
            guard let rule = warnRule(for: event) else { continue }   // genegeerd / geen regel
            if let snz = snoozeUntil[event.id], now < snz { continue }

            let key = event.id + "|" + rule.id.uuidString
            let fireTime = event.start.addingTimeInterval(-Double(rule.leadMinutes) * 60)
            let grace = event.start.addingTimeInterval(120)

            if now >= fireTime, now <= grace, !firedKeys.contains(key) {
                firedKeys.insert(key)
                fire(event: event, rule: rule)
            }
        }

        if firedKeys.count > 300 { firedKeys.removeAll() }
    }

    private func fire(event: UpcomingEvent, rule: MeetingRule) {
        if rule.autoJoin, let url = event.joinURL {
            NSWorkspace.shared.open(url)
        }
        switch rule.alertStyle {
        case .banner:
            BannerNotifier.show(event: event, lang: settingsStore.lang)
        case .fullScreen:
            present(event: event, rule: rule)
        case .ignore:
            break
        }
    }

    /// Legt elk aangesloten scherm vast (alleen bij blur), vóór het overlay verschijnt.
    private func captureBackdrops(for appearance: OverlayAppearance) async -> [CGDirectDisplayID: NSImage] {
        guard appearance.style == .blur else { return [:] }
        var result: [CGDirectDisplayID: NSImage] = [:]
        for screen in NSScreen.screens {
            if let id = screen.bonkDisplayID, let img = await ScreenCapture.capture(displayID: id) {
                result[id] = img
            }
        }
        return result
    }

    /// Toont het schermvullende overlay op alle schermen.
    private func present(event: UpcomingEvent, rule: MeetingRule) {
        let appearance = settingsStore.appearance(for: rule)
        Task { [weak self] in
            guard let self else { return }
            let backs = await self.captureBackdrops(for: appearance)
            self.overlay.show(
                event: event,
                rule: rule,
                appearance: appearance,
                lang: settingsStore.lang,
                backdrops: backs,
                onJoin: { if let u = event.joinURL { NSWorkspace.shared.open(u) } },
                onSnooze: { [weak self] mins in self?.snooze(event: event, minutes: mins) },
                onDismiss: { [weak self] in self?.dismissEvent(event) }
            )
        }
    }

    /// Zet custom reminders om naar events (binnen hetzelfde 48u-venster).
    private func reminderEvents(now: Date) -> [UpcomingEvent] {
        let cal = Calendar.current
        let horizon = now.addingTimeInterval(48 * 3600)
        return settingsStore.settings.reminders.compactMap { reminder -> UpcomingEvent? in
            let end = reminder.date.addingTimeInterval(900)   // 15 min "duur"
            guard end > now, reminder.date < horizon else { return nil }
            let title = reminder.title.trimmingCharacters(in: .whitespaces)
            return UpcomingEvent(
                id: "reminder:\(reminder.id.uuidString)",
                title: title.isEmpty ? "Herinnering" : title,
                start: reminder.date,
                end: end,
                calendarTitle: "Herinnering",
                calendarID: "bonk.reminder",
                isAccepted: true,
                joinURL: nil,
                location: nil,
                notes: reminder.notes.isEmpty ? nil : reminder.notes,
                weekday: cal.component(.weekday, from: reminder.date)
            )
        }
    }

    private func writeDiagnostics(_ events: [UpcomingEvent], now: Date) {
        var lines = [
            "Bonk diagnostics @ \(now)",
            "authorized: \(calendar.authorized)",
            "globalEnabled: \(settingsStore.settings.globalEnabled)",
            "calendars (\(calendar.calendars.count)): \(calendar.calendars.map { $0.title })",
            "enabledCalendarIDs: \(settingsStore.settings.enabledCalendarIDs.isEmpty ? "(alle)" : "\(settingsStore.settings.enabledCalendarIDs.count) gekozen")",
            "upcoming events (48u, niet-allday, niet-geannuleerd): \(events.count)",
            "menuBarStyle: \(settingsStore.settings.menuBarStyle.rawValue)",
            "nextEvent: \(nextEvent.map { "\($0.title) over \(Int($0.start.timeIntervalSinceNow))s" } ?? "geen")",
            "menuBarText: \(menuBarText ?? "nil")",
        ]
        for e in events.prefix(12) {
            lines.append(" - \(e.start) | \(e.title) | cal=\(e.calendarTitle) | accepted=\(e.isAccepted)")
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/bonk-events.log", atomically: true, encoding: .utf8)
    }

    /// Negeer deze meeting: geen waarschuwing, naar de Genegeerd-lijst.
    func skipMeeting(id: String) {
        dismissEvent(id: id)
    }

    /// Maak een eerder genegeerde meeting (handmatig of via regel) weer actief.
    func unskipMeeting(id: String) {
        dismissedIDs.remove(id)
        forceShownIDs.insert(id)   // overschrijft ook een negeer-regel
        saveChoices()
        tick()
    }

    private func saveChoices() {
        UserDefaults.standard.set(Array(dismissedIDs), forKey: dismissedKey)
        UserDefaults.standard.set(Array(forceShownIDs), forKey: forceShownKey)
    }

    private func dismissEvent(_ event: UpcomingEvent) {
        dismissEvent(id: event.id)
    }

    private func dismissEvent(id: String) {
        // Custom herinneringen worden bij negeren verwijderd, niet genegeerd.
        if id.hasPrefix("reminder:") {
            let uuidString = String(id.dropFirst("reminder:".count))
            if let uuid = UUID(uuidString: uuidString) {
                settingsStore.removeReminder(id: uuid)
            }
            tick()
            return
        }
        dismissedIDs.insert(id)
        forceShownIDs.remove(id)
        saveChoices()
        tick()
    }

    private func snooze(event: UpcomingEvent, minutes: Int) {
        snoozeUntil[event.id] = Date().addingTimeInterval(Double(minutes) * 60)
        firedKeys = firedKeys.filter { !$0.hasPrefix(event.id + "|") }
    }

    private var reminderWindow: NSWindow?
    private var shotWindow: NSWindow?

    /// Opent een los venster om snel een herinnering toe te voegen (vanuit het menu).
    func openReminderEditor() {
        let cal = Calendar.current
        let soon = cal.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let date = cal.date(bySetting: .second, value: 0, of: soon) ?? soon
        let reminder = CustomReminder(date: date)

        let view = ReminderEditorView(store: settingsStore, reminder: reminder) { [weak self] in
            self?.reminderWindow?.close()
            self?.reminderWindow = nil
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = L("Nieuwe herinnering", "New reminder", settingsStore.lang)
        win.contentView = NSHostingView(rootView: view)
        win.isReleasedWhenClosed = false
        win.center()
        reminderWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func testOverlay(appearance: OverlayAppearance) {
        let demos = [
            UpcomingEvent(
                id: "demo-1", title: "Sprint Review",
                start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(1860),
                calendarTitle: "Werk", calendarID: "demo", isAccepted: true,
                joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
                location: "AMS-1-02 - The Marble Room (8)\nRTM-1-07 (6)",
                notes: "Laten we weer even syncen over EICON. Ik zal Notion laten notuleren en de samenvatting delen.",
                weekday: 2
            ),
            UpcomingEvent(
                id: "demo-2", title: "1-op-1 met Chris",
                start: Date().addingTimeInterval(60), end: Date().addingTimeInterval(1860),
                calendarTitle: "Q42", calendarID: "demo", isAccepted: true,
                joinURL: URL(string: "https://teams.microsoft.com/l/meetup-join/demo"),
                location: "RTM-1-07 (6)", notes: nil, weekday: 2
            ),
        ]
        Task { [weak self] in
            guard let self else { return }
            let backs = await self.captureBackdrops(for: appearance)
            for demo in demos {
                self.overlay.show(
                    event: demo,
                    rule: self.settingsStore.settings.rules.first ?? MeetingRule(),
                    appearance: appearance,
                    lang: settingsStore.lang,
                    backdrops: backs,
                    onJoin: { if let u = demo.joinURL { NSWorkspace.shared.open(u) } },
                    onSnooze: { _ in },
                    onDismiss: {}
                )
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        func openJoin() {
            if let s = response.notification.request.content.userInfo["joinURL"] as? String,
               let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        }

        switch response.actionIdentifier {
        case BannerNotifier.joinAction, UNNotificationDefaultActionIdentifier:
            openJoin()
        case BannerNotifier.dismissAction, UNNotificationDismissActionIdentifier:
            dismissEvent(id: id)
        default:
            break
        }
    }
}
