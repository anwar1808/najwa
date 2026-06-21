#!/bin/bash
# Build Najwa and assemble a proper .app bundle (status-bar agent).
# Usage: scripts/make_app.sh   → produces ./Najwa.app
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Najwa.app"
CONFIG="${1:-release}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/Najwa"
[ -f "$BIN" ] || { echo "build product not found at $BIN"; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Najwa"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# App icon, if present.
[ -f "$ROOT/Resources/Najwa.icns" ] && cp "$ROOT/Resources/Najwa.icns" "$APP/Contents/Resources/"

echo "==> ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> done: $APP"
echo "Launch with: open \"$APP\"  (then grant Accessibility + Microphone)"
