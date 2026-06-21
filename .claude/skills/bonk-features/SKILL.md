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
  - `SettingsView.swift` — instellingen, tabs: **Algemeen** (`generalTab`: app-info, Bonk aan/uit, taal & weergave, opstarten, updates), **Menubalk** (`menuBarTab`: weergave + markering), **Regels** (`rulesTab`), **Herinneringen** (`remindersTab`), **Weergave** (`AppearanceTab`), **Agenda's** (`calendarsTab`: agendatoegang + selectie/kleuren). Plus `RuleEditorView`, `ReminderEditorView`.
  - `OverlayView.swift` / `OverlayBackgroundView.swift` / `OverlayWindow.swift` — schermvullend alert + achtergrond + venster/`OverlayController`.
  - `BannerNotifier.swift` — `UNUserNotification`-notificaties (meeting + update).
- `app/build.sh` — bouwt/onderteken/installeert/herstart; **bevat de versie** (`CFBundleShortVersionString`/`CFBundleVersion`) in een inline Info.plist.
- `.github/workflows/` — `release-app.yml` (release + DMG bij push naar main die `app/**` raakt) en `deploy-website.yml` (Cloudflare Pages bij `website/**`).
- `website/` — marketingsite (`index.html`, `styles.css`, `assets/`), incl. OG/Twitter preview.

## Features en hun cross-impact

### 1. Menubalk-label (icoon/tekst)
- **Wat:** toont bel-icoon + optioneel tekst voor de eerstvolgende afspraak. Stijlen: `icon`, `countdown`, `titleCountdown`, `titleTime`, `time` (`MenuBarStyle`). Optie "alleen vandaag" (`menuBarOnlyToday`).
- **Waar:** `AppDelegate.menuBarText`, `BonkApp.MenuBarLabel`. Instellingen: **Menubalk**-tab → "Weergave".
- **Raakt / let op:**
  - `MenuBarExtra` rendert het label standaard als **template (monochroom)** → gekleurde achtergronden vallen weg. Daarom wordt bij een markering het label via `ImageRenderer` naar een **niet-template** `NSImage` gerenderd (`MenuBarLabel.renderPill` / `MenuBarPillContent`). Verander je het label, behoud dit.
  - Label ververst alleen omdat `MenuBarLabel` `@ObservedObject var app` observeert en `tick()` elke 15s de `@Published` (nextEvent/upcoming) herzet. Breek die keten niet.
  - Gebruikt `nextEvent` → herinneringen tellen mee.

### 2. Menubalk-markering (gekleurde achtergrond)
- **Wat:** gekleurde capsule achter het label zodra de eerstvolgende afspraak binnen X min valt. Kleur = agenda-kleur, of eigen kleur; **wit** als er meerdere meetings tegelijk uit verschillende agenda's zijn (alleen in agenda-modus).
- **Waar:** `AppDelegate.menuBarHighlightColor` + `calendarColor(_:)`; render in `BonkApp`. Instellingen: **Menubalk**-tab → "Markering". Keys: `menuBarHighlightEnabled`, `menuBarHighlightMinutes`, `menuBarHighlightColorMode` (calendar|custom), `menuBarHighlightColorHex`.
- **Raakt / let op:** agenda-kleur-logica is gespiegeld met `MenuView.calendarColor` (houd ze gelijk). Contrast-voorgrond via `Color.readableForeground`. Werkt ook voor herinneringen (geen agenda → accent paars). Respecteert `globalEnabled` en `menuBarOnlyToday`.

### 3. Menubalk-popover (`MenuView`)
- **Wat:** kop met globale aan/uit-toggle; "Volgende meeting(s)" (meerdere tegelijk = primair), "Daarna", "Genegeerd"; per kaart join-knop, negeer/verwijder (✕), herinnering bewerken (✏️); knoppen Herinnering toevoegen / Instellingen / Afsluiten; **update-banner** bovenaan. Per-agenda kleurstreepje.
- **Waar:** `MenuView.swift`. Reminder-detectie via `event.id.hasPrefix("reminder:")` (✕ = verwijderen; bij meetings = negeren).
- **Raakt / let op:** "Instellingen…" gebruikt `openSettingsReliably()` (accessory-app workaround — niet versimpelen). Join opent `event.joinURL`.

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
- **Wat:** geordende regels; eerste passende regel bepaalt of/hoe gewaarschuwd wordt. Filters: `titleContains`, `onlyAccepted`, `daysOfWeek`, `calendarID`. `leadMinutes`, `alertStyle`, `autoJoin`, `appearanceID`.
- **Waar:** `MeetingRule.matches`, `SettingsStore.rule(for:)`/`firstAlertRule(for:)`/`moveRuleUp/Down`, `RuleEditorView` (rules-tab; volgorde via ▲▼).
- **Raakt / let op:** een regel met specifieke `calendarID` matcht **geen** herinneringen (die hebben `calendarID == "bonk.reminder"`). `.ignore`-regel = stille negeer-regel. Volgorde bepaalt uitkomst.

### 7. Aangepaste herinneringen (`CustomReminder`)
- **Wat:** zelf toegevoegde, tijd-gebonden herinneringen (alleen vandaag; niet in agenda; id-prefix `reminder:`). **Volgen de meeting-regels NIET.** Eén **globale** weergave-instelling geldt voor álle herinneringen: actie (schermvullend/notificatie), minuten vooraf (default 0 = op het tijdstip zelf), weergave-preset, geluid, lock-scherm.
- **Waar:** globale velden in `AppSettings` (`reminderAlertStyle`/`reminderLeadMinutes`/`reminderAppearanceID`/`reminderSound`/`reminderNotifyWhenLocked`); `MeetingEngine.reminderRule(from:)` (vaste `reminderRuleID`) + `MeetingEngine.visibleEvents` (herinneringen áltijd in `upcoming`, nooit in `skipped`); `AppDelegate.tick` splitst agenda-events (regels) en herinneringen (reminderRule); `ReminderEditorView` (tijd/titel/notitie per herinnering); config-sectie "Weergave van herinneringen" in de reminders-tab van `SettingsView`. Beheer via `SettingsStore.add/update/removeReminder`.
- **Raakt / let op:** in het **menu** is de ✕ op een herinnering "verwijderen" (`dismissEvent(id:)` met `reminder:`-prefix → `removeReminder`). In het **schermvullende overlay** heet de knop voor een herinnering **"Sluiten"** (niet "Negeren") en die sluit alléén het overlay (geen verwijderen/negeren) — zie `present(...)` (`onDismiss` no-op voor reminders) en `MeetingCardView.isReminder`. Herinneringen komen **niet** in "Genegeerd". Oudere-dan-vandaag worden in `tick()` opgeruimd. **Samenval met een meeting:** de meeting-layout heeft voorrang — `OverlayController.render` kiest de achtergrond van de eerste níét-reminder meeting, en de herinnering verschijnt als kaart binnen datzelfde overlay. Stuur herinneringen dus **niet** opnieuw door de regel-classificatie (`classify`) — gebruik `visibleEvents`.

### 8. Agenda's & toegang (EventKit)
- **Wat:** leest macOS-gesynchroniseerde agenda's (geen OAuth). Selectie via `enabledCalendarIDs`. Per-agenda kleur in het menu (`calendarColors`).
- **Waar:** `CalendarManager`, Agenda's-tab in `SettingsView` (incl. agendatoegang). `requestFullAccessToEvents`, `EKEventStoreChanged`.
- **Raakt / let op:** **leeg `enabledCalendarIDs` = GEEN agenda-meetings** (na eenmalige migratie `calendarsMigrated` in `AppDelegate.migrateCalendarsIfNeeded`). Verander dit gedrag niet zonder de migratie te herzien. Apple sync-vertraging op Google-wijzigingen kan minuten zijn.

### 9. Join-links
- **Wat:** detecteert Meet/Teams/Zoom-link uit event → join-knop (menu + overlay + notificatie) en optioneel `autoJoin` op starttijd.
- **Waar:** `LinkDetector`, `UpcomingEvent.joinURL`.

### 10. Notificaties (subtiele variant)
- **Wat:** `UNUserNotification` met Joinen/Negeren-acties (categorieën MEETING_JOIN/MEETING) + **update-notificatie** (categorie BONK_UPDATE, actie Downloaden).
- **Waar:** `BannerNotifier.swift`; afhandeling in `AppDelegate.userNotificationCenter(_:didReceive:)`.
- **Raakt / let op:** nieuwe categorie/actie ook in `requestAuth` registreren én in `didReceive` afhandelen. Update-klik opent `updateURL`.

### 11. Update-check
- **Wat:** vergelijkt laatste GitHub-release-tag met `CFBundleShortVersionString` bij start + elke 6u; toont banner in menu, status/knop in Algemeen-tab → Updates, en éénmalige notificatie per versie.
- **Waar:** `UpdateChecker.swift`; `AppDelegate.updateChecker` (`checkIfDue` bij launch én in `tick`). Keys: `BonkUpdateNotifiedVersion.v1`, `BonkUpdateLastCheck.v1`.
- **Raakt / let op:** slaat draft/prerelease over. `isNewer` vergelijkt puntgescheiden getallen. Versie zit in **`build.sh`** (niet in code) → release-workflow leest die. **GitHub rate-limit**: ongeauthenticeerd 60/uur per IP — daarom is de 6u-throttle **bewaard** (`BonkUpdateLastCheck.v1`) zodat herstarts niet bij elke start checken; check **niet** op elke launch forceren. 403 met `X-RateLimit-Remaining: 0` of 429 → `rateLimited` (eigen melding), niet `lastCheckFailed`. Handmatige check negeert de throttle.

### 11b. Geluid per regel + waarschuwen op vergrendeld scherm
- **Wat:** elke niet-negeer-regel heeft een **geluidskeuze** (`notificationSound`: Standaard / systeemgeluid zoals Glass/Ping / Geen) die afgaat bij **elke** waarschuwing van die regel — schermvullend én notificatie. Daarnaast kan een schermvullende regel optioneel een **notificatie op het vergrendelde scherm** tonen (`notifyWhenLocked`), omdat het overlay daar niet zichtbaar is.
- **Waar:** `MeetingRule.notifyWhenLocked` + `notificationSound`; `AlertSound.swift` (`allChoices`/`label`/`play`/`preview`, `screenIsLocked` via `CGSessionCopyCurrentDictionary`); `AppDelegate.fire` (na de alert → altijd `AlertSound.play(rule.notificationSound)`; bij `.fullScreen` + locked + `notifyWhenLocked` → ook `BannerNotifier.show`); rule-editor in `SettingsView` (geluidskiezer + preview-knop altijd zichtbaar; lock-toggle alleen bij schermvullend).
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
4. **Menubalk**: label ververst (countdown loopt), markering kleurt binnen X min (incl. herinnering en multi-agenda = wit), en blijft leesbaar (contrast).
5. **Menu-popover**: volgende/daarna/genegeerd correct; join, negeren (meeting) vs verwijderen (herinnering), herinnering bewerken, update-banner.
6. **Regels**: volgorde-matching klopt; `onlyAccepted`/`daysOfWeek`/`titleContains`/`calendarID` filteren; `.ignore` waarschuwt niet.
7. **Overlay**: schermvullend op hoofdscherm, achtergrond op overige schermen; blur vraagt/gebruikt Screen Recording met fallback; `show*`-toggles werken; meerdere gelijktijdige meetings; ESC sluit (negeert niet).
8. **Agenda's**: lege selectie = geen agenda-meetings; per-agenda kleur; toegang vragen werkt.
9. **Herinneringen**: toevoegen/bewerken/verwijderen via menu én instellingen; gelden alleen vandaag.
10. **Notificaties & update-check**: banner-acties werken; update-melding alleen bij hogere versie, één keer per versie.
11. **Release/website** (indien geraakt): versie in `build.sh` gebumpt vóór push naar main; OG-cache-buster bij beeldwijziging.
