<!--
  Template voor Bonk-release-notes.

  Werkwijze na elke release (de workflow publiceert eerst auto-notes uit commits;
  die vervangen we altijd door een gecureerde versie):
    1. Kopieer dit bestand en vul de secties in — Engels, álle app-features en
       -fixes sinds de vorige tag uitgeschreven, géén website-werk.
    2. Vervang overal X.Y door het versienummer (bv. 1.17). Secties zonder
       inhoud mogen weg.
    3. gh release edit vX.Y --title "Bonk X.Y" --notes-file <bestand>

  De eerste regel is de samenvatting die de website-changelog toont.
  Het HOW TO INSTALL-blok onderaan is VERPLICHT — nooit weglaten of inkorten.
-->

One-sentence summary of this release: what does it bring, in plain words.

## ✨ New

- **Feature name** — what it does and why you'd want it. _Settings → …_ if relevant.

## 🛠 Improved

- **Improvement** — what changed.

## 🐛 Fixed

- **Fix** — what was broken, what happens now.

## 🧪 Under the hood

- Internal changes worth noting (tests, refactors) — optional.

---
> **HOW TO INSTALL**
>
> Download `Bonk-X.Y.dmg` below, open the DMG and drag Bonk to Applications — or install via Homebrew: `brew install --cask kierkels/tap/bonk`. Bonk is ad-hoc signed (no paid Apple Developer account), so macOS can't verify it. The first time you open it, macOS will block it: go to **System Settings → Privacy & Security**, scroll down to the message about Bonk and click **Open Anyway**, then confirm. (Only needed once.) See [Apple's guide](https://support.apple.com/en-us/guide/mac-help/mh40616/mac) if you get stuck.
>
> Requires macOS 14 (Sonoma) or newer.
