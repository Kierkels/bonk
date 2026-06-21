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
    let updateChecker = UpdateChecker()
    private let overlay = OverlayController()

    @Published var nextEvent: UpcomingEvent?
    @Published var upcoming: [UpcomingEvent] = []
    @Published var skipped: [UpcomingEvent] = []

    private var timer: Timer?
    private var wakeTimer: Timer?                    // exacte one-shot timer op het volgende vuurmoment
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
        MeetingEngine.isIgnored(event, rules: settingsStore.settings.rules,
                                dismissed: dismissedIDs, forceShown: forceShownIDs)
    }

    /// De regel die bepaalt hoe gewaarschuwd wordt (nil = niet waarschuwen).
    private func warnRule(for event: UpcomingEvent) -> MeetingRule? {
        MeetingEngine.warnRule(for: event, rules: settingsStore.settings.rules,
                               dismissed: dismissedIDs, forceShown: forceShownIDs)
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

    /// Achtergrondkleur achter het menubalk-icoon wanneer de eerstvolgende meeting
    /// binnen de ingestelde tijd valt. Nil = geen gekleurde markering.
    /// - Agenda-modus: kleur van de agenda; wit als er meerdere meetings tegelijk
    ///   uit verschillende agenda's zijn.
    /// - Eigen modus: de zelfgekozen kleur.
    var menuBarHighlightColor: Color? {
        switch MeetingEngine.highlightChoice(next: nextEvent, upcoming: upcoming,
                                             now: Date(), settings: settingsStore.settings) {
        case .none:               return nil
        case .custom:             return Color(hex: settingsStore.settings.menuBarHighlightColorHex)
        case .white:              return .white
        case .calendar(let id):   return calendarColor(id)
        }
    }

    /// Kleur van een agenda (eventuele eigen kleur uit instellingen, anders die van
    /// de agenda zelf). Spiegelt de logica in het menu.
    private func calendarColor(_ id: String) -> Color {
        if let hex = settingsStore.settings.calendarColors[id] { return Color(hex: hex) }
        if let cal = calendar.calendars.first(where: { $0.calendarIdentifier == id }) {
            return Color(cal.color)
        }
        return Color(hex: "#7C3AED")
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
            updateChecker.checkIfDue(lang: settingsStore.lang)
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
        // Vangnet-controle. Het precieze afvuren gebeurt via de exacte `wakeTimer`;
        // nieuwe afspraken komen via `EKEventStoreChanged` binnen. 30s is daarom
        // ruim genoeg en zuinig (minder wakeups).
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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

        // Agenda-meetings volgen de regels; herinneringen staan los daarvan en
        // volgen de globale herinnering-instellingen.
        let calendarEvents = calendar.upcomingEvents(
            within: 48,
            enabledCalendarIDs: settingsStore.settings.enabledCalendarIDs
        )
        let reminders = reminderEvents(now: now)
        let events = (calendarEvents + reminders).sorted { $0.start < $1.start }

        // Opgeslagen keuzes opschonen zodra meetings uit het venster vallen.
        let ids = Set(events.map { $0.id })
        let before = (dismissedIDs.count, forceShownIDs.count)
        dismissedIDs.formIntersection(ids)
        forceShownIDs.formIntersection(ids)
        if (dismissedIDs.count, forceShownIDs.count) != before { saveChoices() }

        // Toon de meetings waar een regel op past + alle herinneringen; genegeerde apart.
        let classified = MeetingEngine.visibleEvents(calendarEvents: calendarEvents, reminders: reminders,
                                                      now: now, rules: settingsStore.settings.rules,
                                                      dismissed: dismissedIDs, forceShown: forceShownIDs)
        upcoming = classified.upcoming
        nextEvent = classified.next
        skipped = classified.skipped

        writeDiagnostics(events, now: now)

        let reminderRule = MeetingEngine.reminderRule(from: settingsStore.settings)
        var shownReminderIDs: Set<UUID> = []     // getoonde herinneringen → consumeren
        for event in events {
            // Herinneringen volgen de globale herinnering-regel, niet de meeting-regels.
            let rule: MeetingRule?
            if MeetingEngine.isReminderID(event.id) {
                rule = reminderRule.alertStyle == .ignore ? nil : reminderRule
            } else {
                rule = warnRule(for: event)
            }
            guard let rule else { continue }
            let key = event.id + "|" + rule.id.uuidString

            func didFire() {
                firedKeys.insert(key)
                fire(event: event, rule: rule)
                if let uuid = MeetingEngine.reminderUUID(fromEventID: event.id) { shownReminderIDs.insert(uuid) }
            }

            switch MeetingEngine.decision(for: event, rule: rule, now: now,
                                          snoozeUntil: snoozeUntil[event.id],
                                          alreadyFired: firedKeys.contains(key)) {
            case .none, .stillSnoozed:
                continue
            case .fire:
                didFire()
            case .snoozeEnded(let shouldFire):
                snoozeUntil[event.id] = nil
                if shouldFire { didFire() }
            }
        }

        // Een herinnering heeft geen duur: zodra getoond is hij weg (tenzij gesnoozed,
        // dan is hij al verzet). Gemiste herinneringen (app stond uit) ruimen we ook op.
        let graceCutoff = now.addingTimeInterval(-120)
        var remainingReminders = settingsStore.settings.reminders
        remainingReminders.removeAll { shownReminderIDs.contains($0.id) || $0.date < graceCutoff }
        if remainingReminders.count != settingsStore.settings.reminders.count {
            settingsStore.settings.reminders = remainingReminders
        }

        if firedKeys.count > 300 { firedKeys.removeAll() }

        scheduleNextWake(events: events, now: now, reminderRule: reminderRule)
        updateChecker.checkIfDue(lang: settingsStore.lang)
    }

    /// Zet een exacte one-shot timer op het eerstvolgende vuurmoment, zodat een
    /// waarschuwing vrijwel op de seconde komt i.p.v. pas bij de volgende
    /// periodieke controle. De periodieke timer blijft als vangnet bestaan.
    private func scheduleNextWake(events: [UpcomingEvent], now: Date, reminderRule: MeetingRule) {
        wakeTimer?.invalidate()
        wakeTimer = nil
        guard let fireAt = MeetingEngine.nextWake(
            events: events, now: now, rules: settingsStore.settings.rules,
            dismissed: dismissedIDs, forceShown: forceShownIDs,
            reminderRule: reminderRule, snoozeUntil: snoozeUntil
        ) else { return }

        let interval = max(0.05, fireAt.timeIntervalSinceNow + 0.1)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        wakeTimer = t
    }

    private func fire(event: UpcomingEvent, rule: MeetingRule) {
        if rule.autoJoin, let url = event.joinURL {
            NSWorkspace.shared.open(url)
        }
        switch rule.alertStyle {
        case .banner:
            BannerNotifier.show(event: event, lang: settingsStore.lang)
        case .fullScreen:
            // Bij een vergrendeld scherm zie je het overlay toch niet → optioneel
            // een notificatie zodat je het tóch ziet. Het overlay blijft staan en
            // is na het ontgrendelen alsnog zichtbaar.
            if rule.notifyWhenLocked, AlertSound.screenIsLocked {
                BannerNotifier.show(event: event, lang: settingsStore.lang)
            }
            present(event: event, rule: rule)
        case .ignore:
            break
        }
        // Geluid hoort bij élke waarschuwing (notificatie én schermvullend), en
        // werkt ook bij een vergrendeld scherm. Herhalen (alarm) alleen bij
        // schermvullend — daar kun je het stoppen door te reageren.
        if rule.alertStyle != .ignore {
            AlertSound.play(rule.notificationSound,
                            repeating: rule.alertStyle == .fullScreen && rule.repeatSound,
                            forceAudible: rule.overrideMute)
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
                onJoin: { AlertSound.stop(); if let u = event.joinURL { NSWorkspace.shared.open(u) } },
                onSnooze: { [weak self] mins in AlertSound.stop(); self?.snooze(event: event, minutes: mins) },
                // Herinnering: "Sluiten" sluit alleen het overlay (de herinnering blijft
                // staan en wordt niet genegeerd/verwijderd). Meeting: "Negeren".
                onDismiss: { [weak self] in
                    AlertSound.stop()
                    if !MeetingEngine.isReminderID(event.id) { self?.dismissEvent(event) }
                }
            )
        }
    }

    /// Zet custom reminders om naar events. Een herinnering is een momentpunt
    /// (geen duur), dus `end == start`. De levensduur wordt niet via de eindtijd
    /// geregeld maar door consumeren-bij-vuren (in `tick`).
    private func reminderEvents(now: Date) -> [UpcomingEvent] {
        let cal = Calendar.current
        let horizon = now.addingTimeInterval(48 * 3600)
        return settingsStore.settings.reminders.compactMap { reminder -> UpcomingEvent? in
            guard reminder.date < horizon else { return nil }
            let title = reminder.title.trimmingCharacters(in: .whitespaces)
            return UpcomingEvent(
                id: "reminder:\(reminder.id.uuidString)",
                title: title.isEmpty ? "Herinnering" : title,
                start: reminder.date,
                end: reminder.date,
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
        if MeetingEngine.isReminderID(id) {
            if let uuid = MeetingEngine.reminderUUID(fromEventID: id) {
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
        let newDate = Date().addingTimeInterval(Double(minutes) * 60)
        firedKeys = firedKeys.filter { !$0.hasPrefix(event.id + "|") }

        // Herinnering: snoozen = verzetten (hij is bij vuren al verwijderd, dus
        // we plannen 'm opnieuw in op het nieuwe tijdstip). Meeting: gewone snooze.
        if let uuid = MeetingEngine.reminderUUID(fromEventID: event.id) {
            let reminder = CustomReminder(id: uuid, title: event.title,
                                          notes: event.notes ?? "", date: newDate)
            if settingsStore.settings.reminders.contains(where: { $0.id == uuid }) {
                settingsStore.updateReminder(reminder)
            } else {
                settingsStore.addReminder(reminder)
            }
            tick()
            return
        }
        snoozeUntil[event.id] = newDate
    }

    private var reminderWindow: NSWindow?

    /// Opent een los venster om snel een herinnering toe te voegen (vanuit het menu).
    func openReminderEditor() {
        let cal = Calendar.current
        let soon = cal.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let date = cal.date(bySetting: .second, value: 0, of: soon) ?? soon
        presentReminderEditor(CustomReminder(date: date))
    }

    /// Opent de editor voor een bestaande herinnering (vanuit het menu).
    func editReminder(id: String) {
        let uuidString = id.hasPrefix("reminder:") ? String(id.dropFirst("reminder:".count)) : id
        guard let uuid = UUID(uuidString: uuidString),
              let reminder = settingsStore.settings.reminders.first(where: { $0.id == uuid }) else { return }
        presentReminderEditor(reminder)
    }

    private func presentReminderEditor(_ reminder: CustomReminder) {
        let isExisting = settingsStore.settings.reminders.contains { $0.id == reminder.id }
        let view = ReminderEditorView(store: settingsStore, reminder: reminder) { [weak self] in
            self?.reminderWindow?.close()
            self?.reminderWindow = nil
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = isExisting
            ? L("Herinnering bewerken", "Edit reminder", settingsStore.lang)
            : L("Nieuwe herinnering", "New reminder", settingsStore.lang)
        win.contentView = NSHostingView(rootView: view)
        win.isReleasedWhenClosed = false
        win.center()
        reminderWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        let info = response.notification.request.content.userInfo

        // Update-notificatie: klik (of "Downloaden") opent de release-pagina.
        if let s = info["updateURL"] as? String, let url = URL(string: s) {
            if response.actionIdentifier == BannerNotifier.updateAction
                || response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                NSWorkspace.shared.open(url)
            }
            return
        }

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
