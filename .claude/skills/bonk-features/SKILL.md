---
name: bonk-features
description: Feature-map, cross-impact en regressie-checklist voor de Bonk macOS-menubalk-app. Gebruik dit bij ELKE wijziging of review van een Bonk-feature (menubalk, overlay, regels, herinneringen, weergaven/presets, agenda's, notificaties, update-check, lokalisatie, website/CI) om te weten welke andere features geraakt worden en wat je daarna moet controleren.
---

# Bonk — feature-map & impact-gids

Bonk is een macOS-menubalk-app (SwiftUI, Swift Package Manager, geen .xcodeproj, macOS 14+) die je vlak vóór een agenda-meeting waarschuwt met een schermvullend overlay of een notificatie, met one-click joinen. Repo: `Kierkels/bonk` (mappen `app/` en `website/`).

Gebruik deze gids zo: zoek de feature die je raakt → lees "raakt" om te zien wat meeverandert → loop de **Regressie-checklist** onderaan af voor de geraakte onderdelen.

## Architectuur (waar zit wat)

- `app/Sources/Bonk/BonkApp.swift` — `@main`, `MenuBarExtra(.window)` + `Settings`-scene. Bevat **`MenuBarLabel`** (het menubalk-label) en **`MenuBarPillContent`** (gerenderde gekleurde pil).
- `app/Sources/Bonk/AppDelegate.swift` — kern/coördinator: agenda pollen (vangnet-`tick()` elke 30s + `EKEventStoreChanged` + een **exacte one-shot `wakeTimer`** op het volgende vuurmoment via `scheduleNextWake`/`MeetingEngine.nextWake`, zodat waarschuwingen vrijwel op de seconde komen), regels matchen, alerts afvuren, menubalk-tekst/-kleur, herinneringen, negeer-/heractiveer-state, update-check aanjagen, reminder-editor venster. (De live aftelteller in menu/overlay is een SwiftUI-`TimelineView`, puur display — die triggert het afvuren niet.)
- `app/Sources/Bonk/Models/`
  - `SettingsStore.swift` — `AppSettings` (alle instellingen + Codable-migratie) + `SettingsStore` (UserDefaults, `lang`, `colorScheme`, regel-/weergave-/herinnering-beheer). Key: `BonkSettings.v1`.
  - `MeetingEngine.swift` — **pure beslis-logica** (geen UI/AppKit/EventKit): negeren/regels, `classify`, vuur/snooze-`decision`, `highlightChoice`, reminder-id-parsing, agenda-selectie. `AppDelegate` delegeert hiernaartoe → dit is wat de unit-tests dekken.
  - `MeetingRule.swift` — één waarschuwingsregel + `matches(_:)`.
  - `AlertStyle.swift` — `.fullScreen` / `.banner` / `.ignore`.
  - `OverlayAppearance.swift` — weergave-preset (`OverlayBackgroundStyle` gradient/blur/image/solid + scrim/blur/`show*`-toggles) **en** de `Color`-helpers (`init(hex:)`, `hexString`, `readableForeground`, `blended`).
  - `CustomReminder.swift` — zelf toegevoegde herinnering (alleen vandaag).
  - `UpcomingEvent.swift` — genormaliseerd event (agenda-meeting óf herinnering; herinnering-id heeft prefix `reminder:`).
  - `Localization.swift` — `Lang` enum + `L(nl, en, lang)`.
- `app/Sources/Bonk/Calendar/`
  - `CalendarManager.swift` — EventKit-toegang, `calendars`, `upcomingEvents(within:enabledCalendarIDs:)`.
  - `LinkDetector.swift` — Meet/Teams/Zoom-join-URL uit event halen.
  - `ScreenCapture.swift` — ScreenCaptureKit-blur (TCC Screen Recording) + `bonkDisplayID`.
- `app/Sources/Bonk/Services/UpdateChecker.swift` — GitHub-releases checken vs bundle-versie.
- `app/Sources/Bonk/UI/`
  - `MenuView.swift` — menubalk-popover (volgende/daarna/genegeerd, join, negeer/verwijder, reminder bewerken, update-banner).
  - `SettingsView.swift` — instellingen, tabs: **Algemeen** (`generalTab`: app-info, Bonk aan/uit, taal & weergave, opstarten, updates), **Tonen** (enum-case `.menubar` / `menuBarTab` — let op: weergavenaam is "Tonen"/"Display", code-id heet nog `menubar`: sectie "Menubalk" (stijl + `menuBarOnlyToday`) + "Wat tonen" (dagvenster/max) + markering), **Regels** (`rulesTab`), **Herinneringen** (`remindersTab`), **Weergave** (`AppearanceTab`), **Agenda's** (`calendarsTab`: agendatoegang + selectie/kleuren). Plus `RuleEditorView`, `ReminderEditorView`.
  - `OverlayView.swift` / `OverlayBackgroundView.swift` / `OverlayWindow.swift` — schermvullend alert + achtergrond + venster/`OverlayController`.
  - `BannerNotifier.swift` — `UNUserNotification`-notificaties (meeting + update).
- `app/build.sh` — bouwt/onderteken/installeert/herstart; **bevat de versie** (`CFBundleShortVersionString`/`CFBundleVersion`) in een inline Info.plist.
- `.github/workflows/` — `release-app.yml` (release + DMG bij push naar main die `app/**` raakt) en `deploy-website.yml` (Cloudflare Pages bij `website/**`).
- `website/` — marketingsite (`index.html`, `styles.css`, `assets/`), incl. OG/Twitter preview.

## Features en hun cross-impact

### 1. Menubalk-label (icoon/tekst)
- **Wat:** toont bel-icoon + optioneel tekst voor de eerstvolgende afspraak. Stijlen: `icon`, `countdown`, `titleCountdown`, `titleTime`, `time` (`MenuBarStyle`).
- **Waar:** `AppDelegate.menuBarText`, `BonkApp.MenuBarLabel`. Instellingen: **Tonen**-tab → "Weergave".
- **Raakt / let op:**
  - `MenuBarExtra` rendert het label standaard als **template (monochroom)** → gekleurde achtergronden vallen weg. Daarom wordt bij een markering het label via `ImageRenderer` naar een **niet-template** `NSImage` gerenderd (`MenuBarLabel.renderPill` / `MenuBarPillContent`). Verander je het label, behoud dit.
  - Label ververst alleen omdat `MenuBarLabel` `@ObservedObject var app` observeert en `tick()` elke 15s de `@Published` (nextEvent/upcoming) herzet. Breek die keten niet.
  - Gebruikt `nextEvent` → herinneringen tellen mee. `nextEvent`/`upcoming` zijn al beperkt tot het dagvenster (zie feature 1b). Daarnaast is er een **menubalk-specifieke** toggle `menuBarOnlyToday`: staat die aan, dan toont `menuBarText` níéts als de eerstvolgende meeting niet vandaag is (los van het dagvenster dat het menu gebruikt). UI in de **Menubalk**-sectie van de Tonen-tab.

### 1b. Weergavevenster — "toon X dagen" + max aantal meetings
- **Wat:** instelbaar hoeveel er getoond wordt: een dagvenster `displayDays` (1 = alleen vandaag, default) en optioneel een maximum aantal **agenda-meetings** `maxMeetings` (nil = alle, default). Herinneringen tellen **niet** mee voor het max en blijven altijd zichtbaar binnen het venster. Het dagvenster bepaalt zowel de menu-lijst als het venster waarbinnen de menubalk de eerstvolgende meeting kiest; daarnaast is er de menubalk-specifieke `menuBarOnlyToday` (zie feature 1) die de menubalk-tekst/markering tot vandaag beperkt.
- **Waar:** `AppSettings.displayDays`/`maxMeetings`; pure filter `MeetingEngine.displayLimited(_:now:days:maxMeetings:calendar:)` (venster = `startOfDay(now) + days` dagen; herinneringen altijd door); toegepast in `AppDelegate.tick` op `upcoming`/`skipped` → `nextEvent = upcoming.first`. UI in **Tonen**-tab → sectie "Wat tonen" (`displayDays`-stepper + optioneel max via `maxMeetingsEnabled`/`maxMeetingsValue`-bindings in `SettingsView`).
- **Raakt / let op:** dit raakt **alléén de weergave**, niet het vuren. De **ophaalhorizon** volgt `displayDays` via `AppDelegate.fetchHorizonHours(now:)` (= `startOfDay+days`, met **minimaal 48u**) → `calendar.upcomingEvents(within:)`; anders zou "3 dagen" niets extra tonen omdat de data maar 48u ver ging (dat was de bug). Verder weg ophalen vuurt niets vroeg: `decision`/`nextWake` gaten op `leadMinutes`. `MeetingEngine.highlightChoice` filtert **niet** meer op dag (krijgt al een gefilterde `next`). `MenuView.laterSection` heeft géén eigen `prefix(4)`-cap meer — `upcoming` is al begrensd. Reminders zijn today-only → hun 48u-horizon in `reminderEvents` blijft.

### 2. Menubalk-markering (gekleurde achtergrond)
- **Wat:** gekleurde capsule achter het label zodra de eerstvolgende afspraak binnen X min valt. Kleur = agenda-kleur, of eigen kleur; **wit** als er meerdere meetings tegelijk uit verschillende agenda's zijn (alleen in agenda-modus).
- **Waar:** `AppDelegate.menuBarHighlightColor` + `calendarColor(_:)`; render in `BonkApp`. Instellingen: **Tonen**-tab → "Markering". Keys: `menuBarHighlightEnabled`, `menuBarHighlightMinutes`, `menuBarHighlightColorMode` (calendar|custom), `menuBarHighlightColorHex`.
- **Raakt / let op:** agenda-kleur-logica is gespiegeld met `MenuView.calendarColor` (houd ze gelijk). Contrast-voorgrond via `Color.readableForeground`. Werkt ook voor herinneringen (geen agenda → accent paars). Respecteert `globalEnabled`, het dagvenster `displayDays` (via de al-gefilterde `next`/`upcoming`) én `menuBarOnlyToday` (markering ook alleen voor vandaag).

### 3. Menubalk-popover (`MenuView`)
- **Wat:** kop met globale aan/uit-toggle; "Volgende meeting(s)" (meerdere tegelijk = primair), "Daarna", "Genegeerd"; per kaart join-knop, negeer/verwijder (✕), herinnering bewerken (✏️); knoppen Herinnering toevoegen / Instellingen / Afsluiten; **update-banner** bovenaan. Per-agenda kleurstreepje.
- **Waar:** `MenuView.swift`. Reminder-detectie via `event.id.hasPrefix("reminder:")` (✕ = verwijderen; bij meetings = negeren).
- **Raakt / let op:** "Instellingen…" gebruikt `openSettingsReliably()` (accessory-app workaround — niet versimpelen). Join opent `event.joinURL`. De getoonde lijst is begrensd door het dagvenster + max-meetings (feature 1b) — niet meer hard op 4 in "Daarna". De **"Daarna"-lijst is subtiel per dag gegroepeerd**: `MenuView.groupedByDay` (volgorde-behoudend per `startOfDay`) + een dag-kopje `dayHeaderLabel` ("Vandaag"/"Morgen"/"Vrijdag 26 jun"); de rijen (`laterRow`) tonen dan alleen het tijdstip (`clockTime`, niet `shortTime`). Elke dag is een **eigen kaartje** (eigen achtergrond), niet één doorlopende lijst. "Genegeerd" blijft ongegroepeerd (`shortTime` met dag-prefix). De **lege staat** (`MenuView.emptyState`) toont bij een lege lijst een subtiele tweede regel die het dagvenster noemt ("alleen vandaag"/"komende X dagen") en wijst op filters (weergave/agenda's/regels) — alléén als Bonk aan staat.
  - **Valkuil — popover krimpt niet:** `MenuBarExtra(.window)` groeit wel mee met de inhoud maar **krimpt niet** betrouwbaar als die kleiner wordt (bv. weergave 3 dagen → alleen vandaag) → te groot/glitcherig venster. Daarom heeft de root van `MenuView` `.fixedSize(horizontal:false, vertical:true)` + een `.id(layoutKey)` die met de lay-outhoogte meeverandert (authorized, upcoming/skipped-count, aantal daggroepen, update-banner). Verwijder die niet.
  - **Valkuil — agenda-kleurstreepje:** het streepje in `laterRow` is een **leading `.overlay`** met `.frame(width: 3)`, **niet** een `RoundedRectangle`-sibling in de HStack. Reden: als greedy shape-sibling dingt het mee om verticale ruimte en wordt het tot een stompje gecomprimeerd zodra het menu lang is (veel dag-kopjes/kaartjes). Een overlay matcht de rijhoogte en wordt niet gecomprimeerd. Houd dit zo.

### 4. Schermvullend overlay (in-your-face alert)
- **Wat:** borderless venster op `.screenSaver`-niveau, één per `NSScreen` (hoofdscherm = alert, andere = achtergrond-effect). Toont titel (altijd) + optioneel aftelteller/tijd/agenda/geaccepteerd/ruimte/beschrijving. Knoppen: Joinen / Snooze / Negeren. ESC = sluiten (≠ negeren).
- **Waar:** `OverlayView`, `OverlayBackgroundView`, `OverlayWindow`/`OverlayController`; getriggerd via `AppDelegate.fire`→`present`. Per regel een `OverlayAppearance` (preset).
- **Raakt / let op:** blur-stijl legt eerst elk scherm vast (`captureBackdrops` → `ScreenCapture`) vóór tonen → vereist Screen Recording-TCC; val terug op frosted glass als geen toegang. Meerdere gelijktijdige meetings worden samen getoond. `show*`-toggles komen uit de preset.
  - **Stabiliteit bij lock/sleep/unlock & schermwissel:** `OverlayController.relayout()` lijnt de vensters opnieuw uit op de **actuele** `NSScreen.screens` (rebuild als het aantal schermen wijzigt), herberekent `contentIndex` (= huidige `NSScreen.main`) en her-assert frame/level/ordering. Het luistert daarvoor naar `didChangeScreenParametersNotification`, `NSWorkspace.didWake/screensDidWake` en de distributed notification `com.apple.screenIsUnlocked`, plus een vertraagde her-uitlijning (0.3s/1.0s) omdat schermframes na wake/unlock laat settelen. Maak vensters **niet** meer eenmalig met een vaste frame aan — anders komen de oude symptomen terug: scheef venster (stale frame) of "beide schermen geblurd zonder knoppen" (stale `contentIndex` → inhoud op verkeerd/weggevallen scherm).
  - **Snooze:** `AppDelegate.snooze` zet `snoozeUntil[event.id]` en wist de `firedKeys` van dat event; in `tick()` is snooze-afloop een **eigen her-trigger** die opnieuw toont zodra `now >= snoozeUntil` (zolang `event.end > now`), los van het normale venster (start−lead … start+2min). Granulariteit = de 15s-tick. Verkort het venster of verander snooze niet zonder deze her-trigger te behouden, anders komt een snooze die voorbij `start+2min` valt nooit terug.

### 5. Weergave-presets (`OverlayAppearance`)
- **Wat:** herbruikbare uiterlijk-presets (gradient/blur/image/solid, accentkleur, scrim 0–0.8, blur 0–60, en welke velden te tonen). Een regel kan naar een preset wijzen (`appearanceID`).
- **Waar:** `OverlayAppearance.swift`, `AppearanceTab` in `SettingsView.swift`. Beheer in `SettingsStore` (`addAppearance`/`update`/`remove` — minstens één blijft behouden; regels die ernaar wezen vallen terug).
- **Raakt / let op:** alleen relevant bij `alertStyle == .fullScreen`. Voeg je een `show*`-toggle toe: ook in `OverlayView` honoreren én in `AppearanceTab` tonen.

### 6. Waarschuwingsregels (`MeetingRule`)
- **Wat:** geordende regels; eerste passende regel bepaalt of/hoe gewaarschuwd wordt. Filters: `titleContains`, **`attendanceFilter`** (set van `Attendance`; **multiselect** geaccepteerd/uitgenodigd/ter info/afgewezen, leeg = alle), `daysOfWeek`, **`calendarIDs`** (set, multiselect; leeg = alle agenda's). `leadMinutes`, `alertStyle`, `autoJoin`, `appearanceID`.
- **RSVP-status (`Attendance`):** vervangt het oude `isAccepted: Bool`. `UpcomingEvent.attendance` ∈ {`accepted`, `invited`, `declined`, `informational`, `none`}. `CalendarManager.attendance(_:)`: huidige gebruiker in deelnemers → accepted/tentative=accepted, declined, anders invited; géén deelnemers of jij niet als genodigde (gedeelde/jaarkalender) → **`informational`** (níét meer "geaccepteerd"!); herinneringen → `none` (geen badge). Badge in menu (`metaLine`) + overlay (`showAccepted`-toggle, nu "RSVP-status") via `attendance.icon`/`.label`/`.showsBadge`. Migratie: oude `onlyAccepted: true` → `attendanceFilter = [.accepted]` (via `LegacyKeys`). Filter-UI in rule-editor = checkboxes (`Attendance.filterChoices`).
- **Waar:** `MeetingRule.matches`, `SettingsStore.rule(for:)`/`firstAlertRule(for:)`/`moveRuleUp/Down`, `RuleEditorView` (rules-tab; volgorde via ▲▼). De agenda-keuze is een **inline lijst checkboxes** (`.toggleStyle(.checkbox)`, met agenda-kleur-stip per rij + "Alle agenda's" = set leegmaken) — bewust géén `Menu`/dropdown, zodat de selectie altíjd zichtbaar is zonder te openen. De lijst toont **alleen gevolgde agenda's** (`selectableCalendars`: `enabledCalendarIDs` leeg = alle, + reeds-gekozen ids zodat verouderde keuzes afvinkbaar blijven) met footer-hint naar de Agenda's-tab — want filteren op een níét-gevolgde agenda matcht nooit (events worden niet ingelezen). **Twee niveaus, niet verwarren:** `enabledCalendarIDs` (Agenda's-tab) = welke agenda's Bonk überhaupt inleest; `rule.calendarIDs` (regelfilter) = voor welke gevolgde agenda's díe regel geldt.
- **Raakt / let op:** `calendarIDs` verving het oude enkele `calendarID` — migratie in `MeetingRule.init(from:)` leest de legacy-sleutel via `LegacyKeys` en zet 'm om naar een set (custom `CodingKeys` zou `Encodable`-synthese breken, dus níét doen). Een regel met niet-lege `calendarIDs` matcht **geen** herinneringen (die hebben `calendarID == "bonk.reminder"`). `.ignore`-regel = stille negeer-regel. Volgorde bepaalt uitkomst.

### 7. Aangepaste herinneringen (`CustomReminder`)
- **Wat:** zelf toegevoegde herinneringen op een **momentpunt** (geen duur; alleen vandaag; niet in agenda; id-prefix `reminder:`). **Volgen de meeting-regels NIET.** Eén **globale** weergave-instelling geldt voor álle herinneringen: actie (schermvullend/notificatie), minuten vooraf (default 0 = op het tijdstip zelf), weergave-preset, geluid, lock-scherm.
- **Levensduur:** een herinnering heeft **geen eindtijd** (`reminderEvents` zet `end == start`). Hij wordt **getoond en daarna verwijderd** (geconsumeerd): in `tick` markeren de gevuurde herinneringen `shownReminderIDs` → na de fire-loop uit `settings.reminders` verwijderd (gemiste, > grace voorbij, ook). Hij blijft dus **niet** als "Bezig" hangen. **Snoozen = verzetten**: `snooze` voegt de herinnering opnieuw toe op `now + minuten` (i.p.v. de `snoozeUntil`-mechaniek van meetings). Tijdweergave toont alleen het tijdstip als `end <= start` (menu + overlay).
- **Waar:** globale velden in `AppSettings` (`reminderAlertStyle`/`reminderLeadMinutes`/`reminderAppearanceID`/`reminderSound`/`reminderNotifyWhenLocked`); `MeetingEngine.reminderRule(from:)` (vaste `reminderRuleID`) + `MeetingEngine.visibleEvents` (herinneringen áltijd in `upcoming`, nooit in `skipped`); `AppDelegate.tick` splitst agenda-events (regels) en herinneringen (reminderRule); `ReminderEditorView` (tijd/titel/notitie per herinnering); config-sectie "Weergave van herinneringen" in de reminders-tab van `SettingsView`. Beheer via `SettingsStore.add/update/removeReminder`.
- **Raakt / let op:** in het **menu** is de ✕ op een herinnering "verwijderen" (`dismissEvent(id:)` met `reminder:`-prefix → `removeReminder`). In het **schermvullende overlay** heet de knop voor een herinnering **"Sluiten"** (niet "Negeren") en die sluit alléén het overlay (geen verwijderen/negeren) — zie `present(...)` (`onDismiss` no-op voor reminders) en `MeetingCardView.isReminder`. Herinneringen komen **niet** in "Genegeerd". Oudere-dan-vandaag worden in `tick()` opgeruimd. **Samenval met een meeting:** de meeting-layout heeft voorrang — `OverlayController.render` kiest de achtergrond van de eerste níét-reminder meeting, en de herinnering verschijnt als kaart binnen datzelfde overlay. Stuur herinneringen dus **niet** opnieuw door de regel-classificatie (`classify`) — gebruik `visibleEvents`.

### 8. Agenda's & toegang (EventKit)
- **Wat:** leest macOS-gesynchroniseerde agenda's (geen OAuth). Selectie via `enabledCalendarIDs`. Per-agenda kleur in het menu (`calendarColors`).
- **Waar:** `CalendarManager`, Agenda's-tab in `SettingsView` (incl. agendatoegang). `requestFullAccessToEvents`, `EKEventStoreChanged`.
- **Raakt / let op:** **leeg `enabledCalendarIDs` = GEEN agenda-meetings** (na eenmalige migratie `calendarsMigrated` in `AppDelegate.migrateCalendarsIfNeeded`). Verander dit gedrag niet zonder de migratie te herzien. Apple sync-vertraging op Google-wijzigingen kan minuten zijn. De getoonde agendalijst (`CalendarManager.calendars`, gesorteerd op naam) wordt ververst via **`reloadCalendars()`** — bij `requestAccess`, op `EKEventStoreChanged` én in `SettingsView.onAppear` — anders missen later toegevoegde/gesyncte agenda's tot een herstart (gebruikt door zowel de Agenda's-tab als de regel-editor).

### 9. Join-links
- **Wat:** detecteert Meet/Teams/Zoom-link uit event → join-knop (menu + overlay + notificatie) en optioneel `autoJoin` op starttijd.
- **Waar:** `LinkDetector`, `UpcomingEvent.joinURL`.

### 10. Notificaties (subtiele variant)
- **Wat:** `UNUserNotification` met Joinen/Negeren-acties (categorieën MEETING_JOIN/MEETING) + **update-notificatie** (categorie BONK_UPDATE, actie Downloaden).
- **Waar:** `BannerNotifier.swift`; afhandeling in `AppDelegate.userNotificationCenter(_:didReceive:)`.
- **Raakt / let op:** nieuwe categorie/actie ook in `requestAuth` registreren én in `didReceive` afhandelen. Update-klik opent `updateURL`.

### 11. Update-check
- **Wat:** vergelijkt laatste GitHub-release-tag met `CFBundleShortVersionString` bij start + elke 6u; toont banner in menu, status/knop in Algemeen-tab → Updates, en éénmalige notificatie per versie. De **Updates-sectie** toont: huidige **Versie** (`SettingsView.shortVersion`), **Status**-regel, een **"Bekijk wat er nieuw is"-link** naar de release-notes van de geïnstalleerde versie (`SettingsView.releaseNotesURL` → `…/releases/tag/v<versie>`, fallback releases-pagina), en de check-knop. De **menu-banner** (`MenuView.updateBanner`) gebruikt leesbare primary/secondary-tekst (icoon accent-paars + subtiele rand) — géén volledig accent-gekleurde tekst (te laag contrast).
- **Waar:** `UpdateChecker.swift`; `AppDelegate.updateChecker` (`checkIfDue` bij launch én in `tick`). Keys: `BonkUpdateNotifiedVersion.v1`, `BonkUpdateLastCheck.v1`.
- **Raakt / let op:** slaat draft/prerelease over. `isNewer` vergelijkt puntgescheiden getallen. Versie zit in **`build.sh`** (niet in code) → release-workflow leest die. **GitHub rate-limit**: ongeauthenticeerd 60/uur per IP — daarom is de 6u-throttle **bewaard** (`BonkUpdateLastCheck.v1`) zodat herstarts niet bij elke start checken; check **niet** op elke launch forceren. 403 met `X-RateLimit-Remaining: 0` of 429 → `rateLimited` (eigen melding), niet `lastCheckFailed`. Handmatige check negeert de throttle.

### 11b. Geluid per regel + waarschuwen op vergrendeld scherm
- **Wat:** elke niet-negeer-regel heeft een **geluidskeuze** (`notificationSound`: Standaard / systeemgeluid zoals Glass/Ping / Geen) die afgaat bij **elke** waarschuwing van die regel — schermvullend én notificatie. Daarnaast kan een schermvullende regel optioneel een **notificatie op het vergrendelde scherm** tonen (`notifyWhenLocked`), omdat het overlay daar niet zichtbaar is.
- **Waar:** `MeetingRule.notifyWhenLocked` + `notificationSound`; `AlertSound.swift` (`allChoices`/`label`/`play`/`preview`, `screenIsLocked` via `CGSessionCopyCurrentDictionary`); `AppDelegate.fire` (na de alert → altijd `AlertSound.play(rule.notificationSound)`; bij `.fullScreen` + locked + `notifyWhenLocked` → ook `BannerNotifier.show`); rule-editor in `SettingsView` (geluidskiezer + preview-knop altijd zichtbaar; lock-toggle alleen bij schermvullend).
- **Herhalen (alarm):** macOS heeft geen lange/alarm-geluiden; daarom kan een schermvullende regel het geluid **herhalen tot je reageert** (`MeetingRule.repeatSound` / `reminderRepeatSound`). `AlertSound.play(_,repeating:,maxSeconds:)` zet `NSSound.loops = true` (Standaard→`Sosumi`); de cap is **instelbaar** via `MeetingRule.soundMaxSeconds` / `reminderSoundMaxSeconds` (default 30, UI 5 sec…5 min, `SettingsView.soundDurationStepper`, alleen zichtbaar als alarm aanstaat). `AlertSound.stop()` stopt het bij join/snooze/sluiten (in `present`-closures) én bij overlay-`close()`. Alleen schermvullend (een notificatie kun je niet stoppen).
- **Volume:** **géén eigen volume-instelling** — het alarm speelt altijd op het **huidige systeemvolume** (`NSSound.volume` blijft default 1.0). Bewuste keuze: een per-regel volume botste met `overrideMute` en was verwarrend. **Valkuil:** `NSSound(named:)` is een gedeelde cache → altijd via `makeSound` (`.copy()`) afspelen, anders pakt `loops` niet betrouwbaar.
- **Spelen bij gedempte Mac:** `MeetingRule.overrideMute` / `reminderOverrideMute` → `AlertSound.play(_,forceAudible:)`. macOS kan een gewone app niet "door" mute heen laten spelen, dus `SystemAudio.unmuteTemporarily()` (AppleScript) haalt de Mac alléén uit **mute** — het ingestelde volumegetal blijft staan, zodat het alarm op het huidige systeemvolume klinkt — en `AlertSound` her-muet na het geluid (eenmalig: na `duration`; herhalend: bij `stop()`). Geen TCC nodig (`set volume`/mute draait in de osascript zelf). (Bewust geen volume-forcering meer; zie volume-punt hieronder.)
- **Raakt / let op:** Bonk speelt het geluid **zelf** via `NSSound` (`Standaard` = `NSSound.beep()` = systeem-waarschuwingsgeluid), werkt óók bij vergrendeld scherm; **notificaties zijn zelf stil** (`content.sound = nil`) om dubbel geluid te voorkomen. `UNNotificationSound` wordt bewust niet gebruikt (vindt `/System/Library/Sounds` niet). Notificatie is `.timeSensitive`. Zichtbaarheid op het lock screen hangt af van Systeeminstellingen → Notificaties → Bonk; "critical alerts" vereisen een Apple-entitlement (niet bij ad-hoc signing).

### 12. Lokalisatie & weergave
- **Wat:** NL/EN (override of systeem) + licht/donker/systeem.
- **Waar:** `Localization.L`, `SettingsStore.lang`/`colorScheme`; `preferredColorScheme(store.colorScheme)` op elke top-view. Keys: `languageOverride`, `appearanceOverride`.
- **Raakt / let op:** **elke** door de gebruiker zichtbare string moet via `L(nl, en, lang)`. Nieuwe vensters/sheets ook `.preferredColorScheme(store.colorScheme)` geven.

### 13. Opstarten / app-gedrag
- **Wat:** `LSUIElement` (geen Dock-icoon), `SMAppService` launch-at-login, accessory activation policy.
- **Waar:** `build.sh` Info.plist, general-tab "Opstarten".

### 14. Persistentie
- Keys: `BonkSettings.v1` (alle settings, met Codable-migratie via `decodeIfPresent`), `BonkDismissedIDs.v1` (handmatig genegeerd), `BonkForceShownIDs.v1` (weer geactiveerd), `BonkUpdateNotifiedVersion.v1`.
- **Raakt / let op:** nieuw veld in `AppSettings` ⇒ ook in `CodingKeys` én `init(from:)` met `decodeIfPresent` + default (anders breekt oude opslag). `defaults write` werkt niet op een **draaiende** app (in-memory); test via UI of herstart, en `killall cfprefsd` bij externe edits.

### 15. Website & social preview
- **Wat:** marketingsite + OG/Twitter-kaart. `og:image` = gecentreerde merk-kaart (1200×630 JPEG, vierkant-bestendig voor WhatsApp), absolute URL op `bonk-6zr.pages.dev`, met `?v=N` cache-buster.
- **Waar:** `website/index.html` (+ i18n JS), `styles.css`, `assets/og-image.jpg`.
- **Raakt / let op:** WhatsApp/Slack cachen unfurls per URL → bump `?v=N` én deel een verse URL-variant om te hertesten. Tekst die in hero/banner staat ook in de i18n-keys bijwerken.

## Tests (vangnet voor regressies)

- **Waar:** `app/Tests/BonkTests/` (`@testable import Bonk`). Draaien: `swift test --package-path app`. CI: `tests.yml` (elke push/PR op `app/**`) én als **gate** in `release-app.yml` (rode tests blokkeren de release).
- **Wat gedekt is (pure logica):** `MeetingEngine` (negeren/regels, classify, vuur/snooze-`decision` incl. de snooze-na-grace-regressie, `highlightChoice` incl. wit-bij-meerdere-agenda's en reminders, reminder-id, lege-agenda=niets), `MeetingRule.matches`, `LinkDetector.firstURL` (Meet/Zoom/Teams), `UpdateChecker.isNewer`, `Color(hex:)`/`readableForeground`, `CalendarManager.cleanNotes`.
- **Wat NIET door tests gedekt is** (→ skill-checklist + handmatig): UI/`MenuBarExtra`-rendering, TCC, knop-klikgedrag, notificatie-bezorging, launch-at-login, EventKit-sync.
- **Overlay autonoom verifiëren (zonder gebruiker):** maak een echte agenda-afspraak ~75s vooruit (AppleScript Calendar, titel zonder "ios" → matcht de fullScreen-regel), wacht tot vuren, en detecteer het overlay-venster via `CGWindowListCopyWindowInfo` (filter `kCGWindowOwnerName == "Bonk"`, `layer >= CGWindowLevelForKey(.screenSaverWindow)`, full-screen bounds — één venster per scherm). Dit bewijst dat het overlay (en multi-screen) toont, zonder screenshot. Opruimen: event verwijderen + Bonk herstarten. CGWindowList-geometrie vereist géén Screen Recording-TCC.
- **Regel:** raak je beslis-logica aan, doe het in `MeetingEngine` (of een andere pure functie) en **breid de tests uit** — begin met een test die de bug/het nieuwe gedrag vastlegt. Pure functies moeten `nonisolated` zijn als hun type `@MainActor` is (anders niet aanroepbaar vanuit tests).

## Bekende valkuilen (altijd onthouden)
- **Stale build**: oude versie blijft draaien → `./app/build.sh` stopt nu de instance eerst en herstart; controleer `pgrep -xl Bonk` = precies 1 proces.
- **Codesigning/TCC**: ad-hoc onderteken verandert de cdhash per build → Screen Recording-toestemming vervalt. Gebruik de stabiele identiteit **"Bonk Self-Signed Dev"** (`setup-signing.sh`, gebruikt door `build.sh`). In CI = ad-hoc (geen blur-test nodig).
- **MenuBarExtra template-rendering**: zie feature 1 — kleur in de menubalk kan alleen via een niet-template `NSImage`.
- **EventKit-id's**: herinneringen ≠ agenda-meetings; check altijd de `reminder:`-prefix.

## Regressie-checklist (na een wijziging)

1. **Tests**: `swift test --package-path app` is groen; logica-wijzigingen hebben nieuwe/aangepaste tests in `app/Tests/BonkTests/`.
2. **Bouwen**: `./app/build.sh` slaagt (geen warnings genegeerd) en er draait daarna **één** Bonk-proces.
2. **Persistentie**: nieuw settings-veld → `CodingKeys` + `init(from:)` + default aanwezig; bestaande opslag laadt nog.
3. **Lokalisatie + thema**: alle nieuwe strings via `L(...)`; getest in NL en EN; licht én donker.
4. **Menubalk**: label ververst (countdown loopt), markering kleurt binnen X min (incl. herinnering en multi-agenda = wit), en blijft leesbaar (contrast); respecteert `displayDays` (1 = vandaag).
5. **Menu-popover**: volgende/daarna/genegeerd correct; join, negeren (meeting) vs verwijderen (herinnering), herinnering bewerken, update-banner; `displayDays`/`maxMeetings` begrenzen de lijst (max telt alleen meetings, herinneringen altijd zichtbaar; meetings van buiten het venster vuren wél nog).
6. **Regels**: volgorde-matching klopt; `attendanceFilter` (multiselect RSVP)/`daysOfWeek`/`titleContains`/`calendarIDs` (multiselect) filteren; `.ignore` waarschuwt niet. Geluid: max alarm-duur instelbaar (regel én herinneringen); alarm speelt op systeemvolume, "speel ook bij gedempt" un-muet tijdelijk.
7. **Overlay**: schermvullend op hoofdscherm, achtergrond op overige schermen; blur vraagt/gebruikt Screen Recording met fallback; `show*`-toggles werken; meerdere gelijktijdige meetings; ESC sluit (negeert niet).
8. **Agenda's**: lege selectie = geen agenda-meetings; per-agenda kleur; toegang vragen werkt.
9. **Herinneringen**: toevoegen/bewerken/verwijderen via menu én instellingen; gelden alleen vandaag.
10. **Notificaties & update-check**: banner-acties werken; update-melding alleen bij hogere versie, één keer per versie.
11. **Release/website** (indien geraakt): versie in `build.sh` gebumpt vóór push naar main; OG-cache-buster bij beeldwijziging.
