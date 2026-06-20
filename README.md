# Bonk

Een macOS-menubalk-app die je vlak vóór een meeting waarschuwt — schermvullend en
"in your face", of via een subtiele notificatie — met één klik joinen, snoozen of
negeren. Plus de bijbehorende marketingwebsite.

De repo is opgesplitst in twee mappen:

| Map | Inhoud |
|---|---|
| [`app/`](app/) | De Swift-app (SwiftPM-package, `build.sh`, icoon, bronnen). Zie [`app/README.md`](app/README.md). |
| [`website/`](website/) | De statische marketingsite (`index.html`, `styles.css`, `assets/`). |

## Snel starten

```bash
# App bouwen, installeren in /Applications en starten:
./app/build.sh

# Website lokaal bekijken:
open website/index.html
```

## Website-deploy

De site wordt automatisch naar **Cloudflare Pages** gepubliceerd (live op
**https://bonk.kierkels.app**) door de GitHub Action
[`.github/workflows/deploy-website.yml`](.github/workflows/deploy-website.yml),
bij elke push naar `main` die `website/**` raakt (of handmatig via *Run workflow*).

Eenmalige setup: zet de repo-secrets `CLOUDFLARE_API_TOKEN` en
`CLOUDFLARE_ACCOUNT_ID`, en koppel daarna `bonk.kierkels.app` als custom domain
aan het Pages-project `bonk`. Details staan boven in het workflow-bestand.

## App-release

Bij elke push naar `main` die `app/**` raakt bouwt
[`.github/workflows/release-app.yml`](.github/workflows/release-app.yml) `Bonk.app`,
pakt 'm in een `.dmg` en publiceert een GitHub Release met de versie uit de app
(`CFBundleShortVersionString`, ingesteld in [`app/build.sh`](app/build.sh)). Bump
die versie om een nieuw release-tag (`vX.Y`) te maken.

## Licentie

MIT — zie [LICENSE](LICENSE).

© 2026 Roland Kierkels
