---
name: bonk-features
description: Feature-map, cross-impact en regressie-checklist voor de Bonk macOS-menubalk-app. Gebruik dit bij ELKE wijziging of review van een Bonk-feature (menubalk, overlay, regels, herinneringen, weergaven/presets, agenda's, notificaties, update-check, lokalisatie, website/CI) om te weten welke andere features geraakt worden en wat je daarna moet controleren.
---

# Bonk — feature-map & impact-gids

Bonk is een macOS-menubalk-app (SwiftUI, Swift Package Manager, geen .xcodeproj, macOS 14+) die je vlak vóór een agenda-meeting waarschuwt met een schermvullend overlay of een notificatie, met one-click joinen. Repo: `Kierkels/bonk` (mappen `app/` en `website/`).

Gebruik deze gids zo: zoek de feature die je raakt → lees "raakt" om te zien wat meeverandert → loop de **Regressie-checklist** onderaan af voor de geraakte onderdelen.

## Architectuur (waar zit wat)

- `app/Sources/Bonk/BonkApp.swift` — `@main`, `MenuBarExtra(.window)` + `Settings`-scene. Bevat **`MenuBarLabel`** (het menubalk-label) en **`MenuBarPillContent`** (gerenderde gekleurde pil).
- `app/Sources/Bonk/AppDelegate.swift` — kern/coördinator: agenda pollen (`tick()` elke 15s + `EKEventStoreChanged`), regels matchen, alerts afvuren, menubalk-tekst/-kleur, herinneringen, negeer-/heractiveer-state, update-check aanjagen, reminder-editor venster.
- `app/Sources/Bonk/Models/`
  - `SettingsStore.swift` — `AppSettings` (alle instellingen + Codable-migratie) + `SettingsStore` (UserDefaults, `lang`, `colorScheme`, regel-/weergave-/herinnering-beheer). Key: `BonkSettings.v1`.
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
  - `SettingsView.swift` — instellingen (tabs general/rules/reminders/appearance/calendars) + `RuleEditorView`, `ReminderEditorView`, `AppearanceTab`.
  - `OverlayView.swift` / `OverlayBackgroundView.swift` / `OverlayWindow.swift` — schermvullend alert + achtergrond + venster/`OverlayController`.
  - `BannerNotifier.swift` — `UNUserNotification`-notificaties (meeting + update).
- `app/build.sh` — bouwt/onderteken/installeert/herstart; **bevat de versie** (`CFBundleShortVersionString`/`CFBundleVersion`) in een inline Info.plist.
- `.github/workflows/` — `release-app.yml` (release + DMG bij push naar main die `app/**` raakt) en `deploy-website.yml` (Cloudflare Pages bij `website/**`).
- `website/` — marketingsite (`index.html`, `styles.css`, `assets/`), incl. OG/Twitter preview.

## Features en hun cross-impact

### 1. Menubalk-label (icoon/tekst)
- **Wat:** toont bel-icoon + optioneel tekst voor de eerstvolgende afspraak. Stijlen: `icon`, `countdown`, `titleCountdown`, `titleTime`, `time` (`MenuBarStyle`). Optie "alleen vandaag" (`menuBarOnlyToday`).
- **Waar:** `AppDelegate.menuBarText`, `BonkApp.MenuBarLabel`. Instellingen: general-tab → "Menubalk".
- **Raakt / let op:**
  - `MenuBarExtra` rendert het label standaard als **template (monochroom)** → gekleurde achtergronden vallen weg. Daarom wordt bij een markering het label via `ImageRenderer` naar een **niet-template** `NSImage` gerenderd (`MenuBarLabel.renderPill` / `MenuBarPillContent`). Verander je het label, behoud dit.
  - Label ververst alleen omdat `MenuBarLabel` `@ObservedObject var app` observeert en `tick()` elke 15s de `@Published` (nextEvent/upcoming) herzet. Breek die keten niet.
  - Gebruikt `nextEvent` → herinneringen tellen mee.

### 2. Menubalk-markering (gekleurde achtergrond)
- **Wat:** gekleurde capsule achter het label zodra de eerstvolgende afspraak binnen X min valt. Kleur = agenda-kleur, of eigen kleur; **wit** als er meerdere meetings tegelijk uit verschillende agenda's zijn (alleen in agenda-modus).
- **Waar:** `AppDelegate.menuBarHighlightColor` + `calendarColor(_:)`; render in `BonkApp`. Instellingen: general-tab → "Menubalk-markering". Keys: `menuBarHighlightEnabled`, `menuBarHighlightMinutes`, `menuBarHighlightColorMode` (calendar|custom), `menuBarHighlightColorHex`.
- **Raakt / let op:** agenda-kleur-logica is gespiegeld met `MenuView.calendarColor` (houd ze gelijk). Contrast-voorgrond via `Color.readableForeground`. Werkt ook voor herinneringen (geen agenda → accent paars). Respecteert `globalEnabled` en `menuBarOnlyToday`.

### 3. Menubalk-popover (`MenuView`)
- **Wat:** kop met globale aan/uit-toggle; "Volgende meeting(s)" (meerdere tegelijk = primair), "Daarna", "Genegeerd"; per kaart join-knop, negeer/verwijder (✕), herinnering bewerken (✏️); knoppen Herinnering toevoegen / Instellingen / Afsluiten; **update-banner** bovenaan. Per-agenda kleurstreepje.
- **Waar:** `MenuView.swift`. Reminder-detectie via `event.id.hasPrefix("reminder:")` (✕ = verwijderen; bij meetings = negeren).
- **Raakt / let op:** "Instellingen…" gebruikt `openSettingsReliably()` (accessory-app workaround — niet versimpelen). Join opent `event.joinURL`.

### 4. Schermvullend overlay (in-your-face alert)
- **Wat:** borderless venster op `.screenSaver`-niveau, één per `NSScreen` (hoofdscherm = alert, andere = achtergrond-effect). Toont titel (altijd) + optioneel aftelteller/tijd/agenda/geaccepteerd/ruimte/beschrijving. Knoppen: Joinen / Snooze / Negeren. ESC = sluiten (≠ negeren).
- **Waar:** `OverlayView`, `OverlayBackgroundView`, `OverlayWindow`/`OverlayController`; getriggerd via `AppDelegate.fire`→`present`. Per regel een `OverlayAppearance` (preset).
- **Raakt / let op:** blur-stijl legt eerst elk scherm vast (`captureBackdrops` → `ScreenCapture`) vóór tonen → vereist Screen Recording-TCC; val terug op frosted glass als geen toegang. Meerdere gelijktijdige meetings worden samen getoond. `show*`-toggles komen uit de preset.

### 5. Weergave-presets (`OverlayAppearance`)
- **Wat:** herbruikbare uiterlijk-presets (gradient/blur/image/solid, accentkleur, scrim 0–0.8, blur 0–60, en welke velden te tonen). Een regel kan naar een preset wijzen (`appearanceID`).
- **Waar:** `OverlayAppearance.swift`, `AppearanceTab` in `SettingsView.swift`. Beheer in `SettingsStore` (`addAppearance`/`update`/`remove` — minstens één blijft behouden; regels die ernaar wezen vallen terug).
- **Raakt / let op:** alleen relevant bij `alertStyle == .fullScreen`. Voeg je een `show*`-toggle toe: ook in `OverlayView` honoreren én in `AppearanceTab` tonen.

### 6. Waarschuwingsregels (`MeetingRule`)
- **Wat:** geordende regels; eerste passende regel bepaalt of/hoe gewaarschuwd wordt. Filters: `titleContains`, `onlyAccepted`, `daysOfWeek`, `calendarID`. `leadMinutes`, `alertStyle`, `autoJoin`, `appearanceID`.
- **Waar:** `MeetingRule.matches`, `SettingsStore.rule(for:)`/`firstAlertRule(for:)`/`moveRuleUp/Down`, `RuleEditorView` (rules-tab; volgorde via ▲▼).
- **Raakt / let op:** een regel met specifieke `calendarID` matcht **geen** herinneringen (die hebben `calendarID == "bonk.reminder"`). `.ignore`-regel = stille negeer-regel. Volgorde bepaalt uitkomst.

### 7. Aangepaste herinneringen (`CustomReminder`)
- **Wat:** zelf toegevoegde, tijd-gebonden herinneringen (alleen vandaag; niet in agenda). Worden als events behandeld (id-prefix `reminder:`).
- **Waar:** `AppDelegate.reminderEvents` + `openReminderEditor`/`editReminder`/`presentReminderEditor`; `ReminderEditorView` (sheet vanuit reminders-tab óf los venster vanuit menu). Beheer via `SettingsStore.add/update/removeReminder`.
- **Raakt / let op:** een herinnering **negeren = verwijderen** (`dismissEvent(id:)` met `reminder:`-prefix → `removeReminder`); herinneringen komen **niet** in de "Genegeerd"-lijst (alleen agenda-meetings). Oudere-dan-vandaag worden in `tick()` opgeruimd.

### 8. Agenda's & toegang (EventKit)
- **Wat:** leest macOS-gesynchroniseerde agenda's (geen OAuth). Selectie via `enabledCalendarIDs`. Per-agenda kleur in het menu (`calendarColors`).
- **Waar:** `CalendarManager`, calendars-tab in `SettingsView`. `requestFullAccessToEvents`, `EKEventStoreChanged`.
- **Raakt / let op:** **leeg `enabledCalendarIDs` = GEEN agenda-meetings** (na eenmalige migratie `calendarsMigrated` in `AppDelegate.migrateCalendarsIfNeeded`). Verander dit gedrag niet zonder de migratie te herzien. Apple sync-vertraging op Google-wijzigingen kan minuten zijn.

### 9. Join-links
- **Wat:** detecteert Meet/Teams/Zoom-link uit event → join-knop (menu + overlay + notificatie) en optioneel `autoJoin` op starttijd.
- **Waar:** `LinkDetector`, `UpcomingEvent.joinURL`.

### 10. Notificaties (subtiele variant)
- **Wat:** `UNUserNotification` met Joinen/Negeren-acties (categorieën MEETING_JOIN/MEETING) + **update-notificatie** (categorie BONK_UPDATE, actie Downloaden).
- **Waar:** `BannerNotifier.swift`; afhandeling in `AppDelegate.userNotificationCenter(_:didReceive:)`.
- **Raakt / let op:** nieuwe categorie/actie ook in `requestAuth` registreren én in `didReceive` afhandelen. Update-klik opent `updateURL`.

### 11. Update-check
- **Wat:** vergelijkt laatste GitHub-release-tag met `CFBundleShortVersionString` bij start + elke 6u; toont banner in menu, status/knop in general-tab, en éénmalige notificatie per versie.
- **Waar:** `UpdateChecker.swift`; `AppDelegate.updateChecker` (check in `applicationDidFinishLaunching` + `checkIfDue` in `tick`). Key: `BonkUpdateNotifiedVersion.v1`.
- **Raakt / let op:** slaat draft/prerelease over. `isNewer` vergelijkt puntgescheiden getallen. Versie zit in **`build.sh`** (niet in code) → release-workflow leest die.

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

## Bekende valkuilen (altijd onthouden)
- **Stale build**: oude versie blijft draaien → `./app/build.sh` stopt nu de instance eerst en herstart; controleer `pgrep -xl Bonk` = precies 1 proces.
- **Codesigning/TCC**: ad-hoc onderteken verandert de cdhash per build → Screen Recording-toestemming vervalt. Gebruik de stabiele identiteit **"Bonk Self-Signed Dev"** (`setup-signing.sh`, gebruikt door `build.sh`). In CI = ad-hoc (geen blur-test nodig).
- **MenuBarExtra template-rendering**: zie feature 1 — kleur in de menubalk kan alleen via een niet-template `NSImage`.
- **EventKit-id's**: herinneringen ≠ agenda-meetings; check altijd de `reminder:`-prefix.

## Regressie-checklist (na een wijziging)

1. **Bouwen**: `./app/build.sh` slaagt (geen warnings genegeerd) en er draait daarna **één** Bonk-proces.
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
