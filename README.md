# Bonk

Een macOS menubar-app (à la [inyourface.app](https://www.inyourface.app/)) die je
agenda leest en je vlak vóór een meeting waarschuwt — schermvullend en "in your
face", of via een subtiele notificatie. Met één klik joinen (Google Meet / Zoom /
Teams / Webex), snoozen of negeren.

## Bouwen & starten

```bash
./scripts/build-app.sh        # bouwt Bonk.app (release)
open ./Bonk.app               # start de app (menubar-icoon + agenda-prompt)
```

Geef bij de eerste start agendatoegang. De app verschijnt als belletje in de
menubalk (geen dock-icoon). Test het overlay direct via **menubar → "Test-overlay
tonen"**.

## Hoe het werkt

- **Agenda**: leest via EventKit alle agenda's die je Mac synct, inclusief je
  Google-account uit Systeeminstellingen → Internetaccounts. Geen OAuth nodig.
- **Regels** (Instellingen → Regels): meerdere regels, de bovenste passende wint.
  Per regel instelbaar:
  - titel bevat "…"
  - alleen geaccepteerde meetings
  - bepaalde dagen van de week
  - minuten van tevoren
  - stijl: **schermvullend** of **subtiele notificatie**
  - automatisch joinen op starttijd
- **Join-links** worden uit de notities/locatie/URL van de afspraak gehaald
  (Meet, Zoom, Teams, Webex).

## Projectstructuur

```
Sources/Bonk/
  BonkApp.swift            App-entry (MenuBarExtra + Settings-scene)
  AppDelegate.swift        Coördinator: pollt agenda, matcht regels, vuurt alerts
  Models/                  AlertStyle, MeetingRule, UpcomingEvent, SettingsStore
  Calendar/                CalendarManager (EventKit) + LinkDetector
  UI/                      OverlayWindow/View, BannerNotifier, MenuView, SettingsView
Resources/Info.plist       Bundle-config (LSUIElement, agenda-usage strings)
scripts/build-app.sh       Bouwt + bundelt + ad-hoc signeert Bonk.app
```

## Bekende vervolgstappen / ideeën

- Versleepbare regelvolgorde
- Directe Google Calendar API (OAuth) voor rijkere accepted-status/join-links
- Focus-modus respecteren; niet waarschuwen tijdens een lopende meeting
- App-icoon en notarisatie voor distributie
- Negeerlijst op trefwoord (bv. `[hold]`, `lunch`)
