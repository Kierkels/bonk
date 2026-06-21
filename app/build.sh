#!/usr/bin/env bash
# Builds Bonk.app — a self-contained menu-bar agent bundle.
#
# Versie bumpen = pas CFBundleShortVersionString / CFBundleVersion hieronder aan;
# een push naar main die app/** raakt maakt dan automatisch een nieuwe release
# met die versie (zie .github/workflows/release-app.yml).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Bonk"
APP="${APP_NAME}.app"
BIN_NAME="Bonk"   # Swift product name (matcht Package.swift)

echo "▸ Compiling (release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="${BIN_DIR}/${BIN_NAME}"

echo "▸ Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"
cp AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Bonk</string>
    <key>CFBundleDisplayName</key>        <string>Bonk</string>
    <key>CFBundleIdentifier</key>         <string>nl.roland.bonk</string>
    <key>CFBundleExecutable</key>         <string>Bonk</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.1</string>
    <key>CFBundleVersion</key>            <string>2</string>
    <key>NSHumanReadableCopyright</key>   <string>© 2026 Roland Kierkels</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key> <string>Bonk leest je agenda om je vlak voor een meeting te waarschuwen.</string>
    <key>NSCalendarsUsageDescription</key>           <string>Bonk leest je agenda om je vlak voor een meeting te waarschuwen.</string>
</dict>
</plist>
PLIST

# Onderteken: gebruik de stabiele zelf-ondertekende identiteit als die er is
# (zodat schermopname-toestemming behouden blijft over builds heen), anders
# ad-hoc. In CI bestaat de identiteit niet → ad-hoc.
IDENTITY="Bonk Self-Signed Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "▸ Ondertekenen met '${IDENTITY}'…"
  codesign --force --deep --sign "$IDENTITY" "${APP}" >/dev/null 2>&1 || true
else
  echo "▸ Ad-hoc ondertekenen…"
  codesign --force --deep --sign - "${APP}" >/dev/null 2>&1 || true
fi

# In CI (GitHub Actions zet CI=true) willen we alleen de assembled bundle — de
# release-workflow pakt 'm in een DMG. Sla install + launch over.
if [ -n "${CI:-}" ]; then
  echo "✓ Built ${APP} (CI: skipping install/launch)"
  exit 0
fi

echo "▸ Huidige instance stoppen…"
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -x "${BIN_NAME}" >/dev/null 2>&1 || true
# Wacht tot het proces echt weg is (max ~3s) zodat er geen dubbele
# menubalk-instance ontstaat als we meteen opnieuw starten.
for _ in $(seq 1 30); do
  pgrep -x "${BIN_NAME}" >/dev/null 2>&1 || break
  sleep 0.1
done
pkill -9 -x "${BIN_NAME}" >/dev/null 2>&1 || true

echo "▸ Installeren in /Applications…"
rm -rf "/Applications/${APP}"
cp -R "${APP}" "/Applications/${APP}"

echo "▸ Starten…"
open -n "/Applications/${APP}"

echo "✓ Built, geïnstalleerd en gestart: /Applications/${APP}"
echo "  Autostart: Instellingen → Algemeen → Starten bij inloggen"
