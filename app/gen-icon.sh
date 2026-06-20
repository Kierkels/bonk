#!/usr/bin/env bash
# Genereert AppIcon.icns uit gen_icon.swift (comic impact-burst icoon).
set -euo pipefail
cd "$(dirname "$0")"
echo "==> PNG's genereren (Bonk.iconset)"
swift gen_icon.swift
echo "==> .icns bouwen"
iconutil -c icns Bonk.iconset -o AppIcon.icns
echo "==> klaar: app/AppIcon.icns"
