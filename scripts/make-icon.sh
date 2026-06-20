#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> PNG's genereren (Bonk.iconset)"
swift scripts/make-icon.swift

echo "==> .icns bouwen"
mkdir -p Resources
iconutil -c icns Bonk.iconset -o Resources/Bonk.icns

echo "==> klaar: Resources/Bonk.icns"
