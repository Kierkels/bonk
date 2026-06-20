# Bonk (app)

Native macOS menubar-app (SwiftUI + Swift Package Manager) die je agenda leest en
je vlak vóór een meeting waarschuwt — schermvullend of via een notificatie — met
joinen, snoozen en negeren.

## Bouwen & starten

```bash
./build.sh          # compileert, assembleert Bonk.app, installeert in /Applications en start
```

In CI (GitHub Actions) wordt `CI=true` gezet; dan assembleert `build.sh` alleen de
bundel (geen install/launch) en pakt de release-workflow 'm in een DMG.

De **versie** staat in `build.sh` (`CFBundleShortVersionString` / `CFBundleVersion`)
en is zichtbaar in de app onder **Instellingen → Algemeen**.

## Icoon

```bash
./gen-icon.sh       # gen_icon.swift → Bonk.iconset → AppIcon.icns
```

`AppIcon.icns` is gecommit zodat de app direct te bouwen is; regenereer alleen bij
een icoonwijziging.

## Permissies & ondertekening

- **Agenda** via EventKit (geen OAuth) — pikt gesyncte Google/iCloud/Exchange-agenda's mee.
- **Schermopname** (alleen voor de instelbare blur-achtergrond) — optioneel; valt anders
  terug op frosted-glass.
- Lokaal ondertekent `build.sh` met een stabiele zelf-ondertekende identiteit als die
  bestaat (zodat toestemmingen blijven kleven over builds heen); anders ad-hoc. Zet 'm
  eenmalig op met `./setup-signing.sh`. In CI is het ad-hoc.

## Structuur

```
app/
  Package.swift
  Sources/Bonk/
    BonkApp.swift            App-entry (MenuBarExtra + Settings-scene)
    AppDelegate.swift        Coördinator: pollt agenda, matcht regels, vuurt alerts
    Models/                  AlertStyle, MeetingRule, OverlayAppearance, CustomReminder,
                             SettingsStore, UpcomingEvent, Localization
    Calendar/                CalendarManager (EventKit), LinkDetector, ScreenCapture
    UI/                      Overlay (window/view/background), MenuView, SettingsView,
                             BannerNotifier
  AppIcon.icns               Gecommit app-icoon
  build.sh                   Bouw + bundel + onderteken + (lokaal) installeren
  gen_icon.swift / gen-icon.sh   Icoon-generator
  setup-signing.sh           Eenmalige stabiele zelf-ondertekende identiteit (dev)
```
