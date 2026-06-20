#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="Bonk.app"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Bonk"

echo "==> bundelen naar $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bonk"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "Resources/Bonk.icns" ]; then
    cp "Resources/Bonk.icns" "$APP/Contents/Resources/Bonk.icns"
fi

IDENTITY="Bonk Self-Signed Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> ondertekenen met '$IDENTITY' (stabiel)"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "==> ad-hoc ondertekenen (tip: ./scripts/setup-signing.sh voor blijvende permissies)"
    codesign --force --deep --sign - "$APP"
fi

echo "==> klaar: $ROOT/$APP"
echo "    Starten met:  open \"$ROOT/$APP\""
