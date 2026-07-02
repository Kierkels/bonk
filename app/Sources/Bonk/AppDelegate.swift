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
    private let pill = PillController()
    private let hotKey = HotKeyManager()

    @Published var nextEvent: UpcomingEvent?
    @Published var upcoming: [UpcomingEvent] = []
    @Published var skipped: [UpcomingEvent] = []

    private var timer: Timer?
    private var wakeTimer: Timer?                    // exacte one-shot timer op het volgende vuurmoment
    private var firedKeys: Set<String> = []
    private var snoozeUntil: [String: Date] = [:]
    // Genegeerde/heractiveerde keuzes, bewaard met de einddatum van de meeting,
    // zodat een keuze pas wordt opgeschoond als de meeting echt voorbij is — los
    // van het (kleinere) dagvenster dat de gebruiker toevallig toont.
    private var dismissedEnds: [String: Date] = [:]   // handmatig genegeerd
    private var forceShownEnds: [String: Date] = [:]  // weer geactiveerd (overschrijft negeer-regel)
    private var dismissedIDs: Set<String> { Set(dismissedEnds.keys) }
    private var forceShownIDs: Set<String> { Set(forceShownEnds.keys) }
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

    /// SF Symbol-naam voor het gekozen menubalk-icoon.
    var menuBarIconName: String { settingsStore.settings.menuBarIcon.symbolName }

    /// Bonk is gepauzeerd (globaal uitgezet): toont niets en waarschuwt nergens voor.
    var isPaused: Bool { !settingsStore.settings.globalEnabled }

    /// Tekst voor in de menubalk, afhankelijk van de gekozen stijl.
    var menuBarText: String? {
        let style = settingsStore.settings.menuBarStyle
        // `nextEvent` is al beperkt tot het ingestelde dagvenster (zie tick).
        guard style != .icon, let n = nextEvent else { return nil }
        // Menubalk-tekst optioneel alleen voor meetings van vandaag (los van het
        // dagvenster dat het menu gebruikt).
        if settingsStore.settings.menuBarOnlyToday,
           !Calendar.current.isDateInToday(n.start) { return nil }

        let cd = shortCountdown(n.start)
        let time = menuBarTime(n.start)

        // Meerdere meetings tegelijk → toon aantal i.p.v. één titel.
        let simultaneous = upcoming.filter { abs($0.start.timeIntervalSince(n.start)) < 60 }.count
        let titlePart = simultaneous > 1 ? "\(simultaneous) meetings" : truncatedTitle(n.title)

        // Eenmaal begonnen is een aftelling ("bezig") weinig zinvol → toon gewoon de
        // titel, ongeacht de stijl, totdat de meeting/herinnering wordt gejoined,
        // genegeerd of gesloten (dan valt 'ie uit `nextEvent`).
        if n.start <= Date() { return titlePart }

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

    /// Accentkleur voor de pill: agenda-kleur voor meetings, accent-paars voor herinneringen.
    private func pillAccent(for event: UpcomingEvent) -> Color {
        MeetingEngine.isReminderID(event.id) ? Color(hex: "#7C3AED") : calendarColor(event.calendarID)
    }

    private func truncatedTitle(_ title: String, max: Int = 24) -> String {
        title.count > max ? String(title.prefix(max - 1)) + "…" : title
    }

    private func shortCountdown(_ date: Date) -> String {
        MeetingEngine.compactCountdown(to: date, now: Date(), lang: settingsStore.lang)
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
        dismissedEnds = Self.loadChoices(forKey: dismissedKey)
        forceShownEnds = Self.loadChoices(forKey: forceShownKey)
        UNUserNotificationCenter.current().delegate = self
        BannerNotifier.requestAuth(lang: settingsStore.lang)
        hotKey.onTrigger = { [weak self] in self?.openReminderEditor() }
        applyQuickReminderShortcut()
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
                DispatchQueue.main.async {
                    self?.tick()
                    self?.applyQuickReminderShortcut()
                }
            }
            .store(in: &cancellables)
    }

    /// (Her)registreert de globale sneltoets voor "nieuwe herinnering".
    private func applyQuickReminderShortcut() {
        hotKey.update(settingsStore.settings.quickReminderShortcut)
    }

    /// Reageer direct op agenda-wijzigingen (toevoegen/wijzigen/sync) i.p.v. te
    /// wachten op de volgende timer-tick.
    private func observeCalendarChanges() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: calendar.store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.calendar.reloadCalendars()   // nieuwe/gesyncte agenda's tonen
                self?.tick()
            }
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
        let graceCutoff = now.addingTimeInterval(-120)

        // Herinneringen normaliseren:
        //  - eenmalig & van een eerdere dag → opruimen;
        //  - herhalend & ruim voorbij → naar het eerstvolgende vuurmoment schuiven
        //    (binnen de grace blijft 'ie staan zodat de fire-loop hieronder 'm nog
        //    kan tonen).
        let startOfToday = Calendar.current.startOfDay(for: now)
        var normalized = settingsStore.settings.reminders
        var normalizedChanged = false
        normalized = normalized.compactMap { r -> CustomReminder? in
            if r.isRepeating {
                if r.date < graceCutoff, let next = r.nextOccurrence(onOrAfter: now), next != r.date {
                    advanceFiredKeys(forReminder: r.id)
                    normalizedChanged = true
                    var c = r; c.date = next; return c
                }
                return r
            } else {
                let snoozedFuture = (snoozeUntil["reminder:\(r.id.uuidString)"] ?? .distantPast) > now
                if !snoozedFuture, r.date < startOfToday { normalizedChanged = true; return nil }
                return r
            }
        }
        if normalizedChanged { settingsStore.settings.reminders = normalized }

        // Agenda-meetings volgen de regels; herinneringen staan los daarvan en
        // volgen de globale herinnering-instellingen.
        // Haal genoeg vooruit op om het ingestelde dagvenster te kunnen vullen
        // (minimaal 48u — voor het vuren van meetings net buiten "vandaag").
        let calendarEvents = calendar.upcomingEvents(
            within: fetchHorizonHours(now: now),
            enabledCalendarIDs: settingsStore.settings.enabledCalendarIDs
        )
        let reminders = reminderEvents(now: now)
        let events = (calendarEvents + reminders).sorted { $0.start < $1.start }

        // Genegeerde/heractiveerde keuzes onderhouden op basis van de meeting-datum,
        // niet het opgehaalde venster: ververs de bewaarde einddatum voor meetings
        // die nu in beeld zijn (vangt ook gemigreerde/verzette meetings op) en gooi
        // een keuze pas weg als de meeting echt is afgelopen.
        var choicesChanged = false
        for event in events {
            if dismissedEnds[event.id] != nil, dismissedEnds[event.id] != event.end {
                dismissedEnds[event.id] = event.end; choicesChanged = true
            }
            if forceShownEnds[event.id] != nil, forceShownEnds[event.id] != event.end {
                forceShownEnds[event.id] = event.end; choicesChanged = true
            }
        }
        let prunedDismissed = dismissedEnds.filter { $0.value > now }
        let prunedForce = forceShownEnds.filter { $0.value > now }
        if prunedDismissed.count != dismissedEnds.count || prunedForce.count != forceShownEnds.count {
            choicesChanged = true
        }
        dismissedEnds = prunedDismissed
        forceShownEnds = prunedForce
        if choicesChanged { saveChoices() }

        // Toon de meetings waar een regel op past + alle herinneringen; genegeerde apart.
        let classified = MeetingEngine.visibleEvents(calendarEvents: calendarEvents, reminders: reminders,
                                                      now: now, rules: settingsStore.settings.rules,
                                                      dismissed: dismissedIDs, forceShown: forceShownIDs)
        // Dagvenster + optioneel max — raakt alléén de weergave (menu + menubalk),
        // niet het vuren hieronder (dat blijft over het volledige venster lopen).
        let days = settingsStore.settings.displayDays
        let maxMeetings = settingsStore.settings.maxMeetings
        upcoming = MeetingEngine.displayLimited(classified.upcoming, now: now, days: days, maxMeetings: maxMeetings)
        nextEvent = upcoming.first
        skipped = MeetingEngine.displayLimited(classified.skipped, now: now, days: days, maxMeetings: nil)

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

        // Een eenmalige herinnering heeft geen duur: zodra getoond (of gemist omdat
        // de app uitstond) is hij weg. Een herhalende herinnering verzetten we naar
        // het eerstvolgende vuurmoment i.p.v. te verwijderen.
        var updatedReminders = settingsStore.settings.reminders
        var remindersChanged = false
        updatedReminders = updatedReminders.compactMap { r -> CustomReminder? in
            let snoozedFuture = (snoozeUntil["reminder:\(r.id.uuidString)"] ?? .distantPast) > now
            let fired = shownReminderIDs.contains(r.id)
            // Een gesnoozede herinnering nooit als "gemist" opruimen — ze wacht op
            // haar snooze-moment, ook al ligt de weergavetijd al in het verleden.
            let missed = !snoozedFuture && r.date < graceCutoff
            guard fired || missed else { return r }
            if r.isRepeating {
                // Na het vuren net iets voorbij 'now' zoeken zodat we niet hetzelfde
                // moment opnieuw pakken.
                let from = fired ? now.addingTimeInterval(1) : now
                guard let next = r.nextOccurrence(onOrAfter: from), next != r.date else { return r }
                advanceFiredKeys(forReminder: r.id)
                remindersChanged = true
                var c = r; c.date = next; return c
            } else {
                remindersChanged = true
                return nil
            }
        }
        if remindersChanged { settingsStore.settings.reminders = updatedReminders }

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
            // De subtiele waarschuwing is nu een pill (met join/snooze/open-in-agenda).
            pill.show(
                event: event,
                accent: pillAccent(for: event),
                lang: settingsStore.lang,
                colorScheme: settingsStore.colorScheme,
                onJoin: { AlertSound.stop(); if let u = event.joinURL { NSWorkspace.shared.open(u) } },
                onSnooze: { [weak self] (mins: Int) in AlertSound.stop(); self?.snooze(event: event, minutes: mins) },
                onSnoozeUntilStart: { [weak self] in AlertSound.stop(); self?.snoozeUntilStart(event: event) },
                onDismiss: { AlertSound.stop() },
                onOpenCalendar: { if let u = event.calendarItemURL { NSWorkspace.shared.open(u) } }
            )
            // Vangnet: op een vergrendeld scherm is de pill niet zichtbaar → notificatie.
            if AlertSound.screenIsLocked {
                BannerNotifier.show(event: event, lang: settingsStore.lang)
            }
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
                            maxSeconds: rule.soundMaxSeconds,
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
                onSnooze: { [weak self] (mins: Int) in AlertSound.stop(); self?.snooze(event: event, minutes: mins) },
                onSnoozeUntilStart: { [weak self] in AlertSound.stop(); self?.snoozeUntilStart(event: event) },
                // "Sluiten" sluit alléén het overlay — zowel voor herinneringen als
                // meetings. Negeren kan uitsluitend vanuit het menu (✕ op een kaart).
                onDismiss: { AlertSound.stop() }
            )
        }
    }

    /// Zet custom reminders om naar events. Een herinnering is een momentpunt
    /// (geen duur), dus `end == start`. De levensduur wordt niet via de eindtijd
    /// geregeld maar door consumeren-bij-vuren (in `tick`).
    /// Hoeveel uur vooruit agenda-events op te halen, zodat het ingestelde
    /// dagvenster (`displayDays`) volledig gevuld kan worden. Minimaal 48u, zodat
    /// meetings net buiten "vandaag" nog op tijd kunnen vuren.
    private func fetchHorizonHours(now: Date) -> Int {
        // Genoeg vooruit om het ingestelde dagvenster te vullen (minimaal 48u voor
        // het vuren van meetings net buiten "vandaag"). Het bewaren van genegeerde/
        // heractiveerde keuzes hangt hier níét van af — dat gaat op meeting-datum
        // (zie `tick`) — dus dit venster mag rustig met `displayDays` meekrimpen.
        let days = max(1, settingsStore.settings.displayDays)
        let startOfToday = Calendar.current.startOfDay(for: now)
        let windowEnd = Calendar.current.date(byAdding: .day, value: days, to: startOfToday) ?? now
        let hours = Int((windowEnd.timeIntervalSince(now) / 3600).rounded(.up))
        return max(48, hours)
    }

    private func reminderEvents(now: Date) -> [UpcomingEvent] {
        let cal = Calendar.current
        // Zelfde horizon als de agenda-meetings, zodat herinneringen verder vooruit
        // (incl. wekelijkse) net zo goed in het venster passen.
        let horizon = now.addingTimeInterval(Double(fetchHorizonHours(now: now)) * 3600)
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
                attendance: .none, // herinneringen hebben geen RSVP → geen badge
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
            lines.append(" - \(e.start) | \(e.title) | cal=\(e.calendarTitle) | rsvp=\(e.attendance.rawValue)")
        }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/bonk-events.log", atomically: true, encoding: .utf8)
    }

    /// Negeer deze meeting: geen waarschuwing, naar de Genegeerd-lijst.
    func skipMeeting(id: String) {
        dismissEvent(id: id)
    }

    /// Maak een eerder genegeerde meeting (handmatig of via regel) weer actief.
    func unskipMeeting(id: String) {
        dismissedEnds[id] = nil
        forceShownEnds[id] = eventEnd(forID: id)   // overschrijft ook een negeer-regel
        saveChoices()
        tick()
    }

    /// Einddatum van een meeting die nu in beeld is, om een keuze mee te bewaren.
    /// Valt terug op ‘ver in de toekomst’ zodat de keuze niet meteen wordt
    /// opgeschoond mocht de meeting (zeldzaam) niet gevonden worden.
    private func eventEnd(forID id: String) -> Date {
        (upcoming + skipped).first { $0.id == id }?.end ?? .distantFuture
    }

    private func saveChoices() {
        UserDefaults.standard.set(dismissedEnds.mapValues { $0.timeIntervalSince1970 }, forKey: dismissedKey)
        UserDefaults.standard.set(forceShownEnds.mapValues { $0.timeIntervalSince1970 }, forKey: forceShownKey)
    }

    /// Laadt bewaarde keuzes (id → einddatum). Migreert het oude `[String]`-formaat:
    /// datum onbekend → ver in de toekomst, zodat bestaande keuzes niet meteen
    /// worden opgeschoond (ze krijgen hun echte einddatum zodra de meeting weer in
    /// beeld komt).
    private static func loadChoices(forKey key: String) -> [String: Date] {
        let d = UserDefaults.standard
        if let raw = d.dictionary(forKey: key) {
            return raw.compactMapValues { ($0 as? Double).map(Date.init(timeIntervalSince1970:)) }
        }
        if let arr = d.stringArray(forKey: key) {
            return Dictionary(uniqueKeysWithValues: arr.map { ($0, Date.distantFuture) })
        }
        return [:]
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
        dismissedEnds[id] = eventEnd(forID: id)
        forceShownEnds[id] = nil
        saveChoices()
        tick()
    }

    /// Verwijdert de "al gevuurd"-markeringen van een herinnering, zodat een
    /// verzette/herhalende herinnering op z'n nieuwe tijdstip opnieuw kan vuren.
    private func advanceFiredKeys(forReminder id: UUID) {
        let prefix = "reminder:\(id.uuidString)|"
        firedKeys = firedKeys.filter { !$0.hasPrefix(prefix) }
    }

    private func snooze(event: UpcomingEvent, minutes: Int) {
        let newDate = Date().addingTimeInterval(Double(minutes) * 60)
        firedKeys = firedKeys.filter { !$0.hasPrefix(event.id + "|") }

        // Herinnering: snoozen verzet NIET de weergavetijd — die blijft op het
        // ingestelde tijdstip staan (de teller loopt daarna negatief, "al begonnen").
        // Alleen `snoozeUntil` bepaalt wanneer de melding terugkomt; de globale
        // lead-tijd wordt daarbij bewust genegeerd. De herinnering wordt zo nodig
        // opnieuw ingepland (ze is bij het vuren mogelijk al verwijderd) zodat ze
        // blijft bestaan tot je ze écht sluit.
        if let uuid = MeetingEngine.reminderUUID(fromEventID: event.id) {
            if !settingsStore.settings.reminders.contains(where: { $0.id == uuid }) {
                settingsStore.addReminder(CustomReminder(id: uuid, title: event.title,
                                                         notes: event.notes ?? "", date: event.start))
            }
            snoozeUntil[event.id] = newDate
            tick()
            return
        }
        snoozeUntil[event.id] = newDate
    }

    /// Snooze tot de starttijd: de waarschuwing komt opnieuw zodra de
    /// meeting/herinnering begint. Alleen zinvol als de waarschuwing vóór de start
    /// werd getoond — anders is `event.start` al voorbij en gebeurt er niets.
    private func snoozeUntilStart(event: UpcomingEvent) {
        firedKeys = firedKeys.filter { !$0.hasPrefix(event.id + "|") }

        // Een herinnering is bij het vuren mogelijk al uit de opslag verwijderd
        // (eenmalig) of doorgeschoven (herhalend) → plan 'm opnieuw op de starttijd.
        // `snoozeUntil` onderdrukt daarbij een eventuele vroege lead-waarschuwing,
        // zodat de melding precies op het ingestelde tijdstip terugkomt.
        if let uuid = MeetingEngine.reminderUUID(fromEventID: event.id) {
            if var existing = settingsStore.settings.reminders.first(where: { $0.id == uuid }) {
                existing.date = event.start
                settingsStore.updateReminder(existing)
            } else {
                settingsStore.addReminder(CustomReminder(id: uuid, title: event.title,
                                                         notes: event.notes ?? "", date: event.start))
            }
        }

        snoozeUntil[event.id] = event.start
        tick()
    }

    private var reminderWindow: NSWindow?

    /// Opent een los venster om snel een herinnering toe te voegen (vanuit het menu).
    func openReminderEditor() {
        // Geen herinneringen toevoegen als Bonk uitstaat (ook niet via de sneltoets).
        guard settingsStore.settings.globalEnabled else { return }
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
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
