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

# Sign with a stable self-signed identity ("Najwa Dev") so the Accessibility /
# Microphone grants survive rebuilds. Falls back to ad-hoc if it isn't present.
SIGN_ID=$(security find-certificate -c "Najwa Dev" -Z 2>/dev/null | awk '/SHA-1/{print $3}')
if [ -n "$SIGN_ID" ]; then
  echo "==> code signing with stable identity: Najwa Dev ($SIGN_ID)"
  codesign --force --deep --sign "$SIGN_ID" "$APP"
else
  echo "==> ad-hoc code signing (no 'Najwa Dev' identity found)"
  codesign --force --deep --sign - "$APP"
fi

echo "==> done: $APP"
echo "Launch with: open \"$APP\"  (then grant Accessibility + Microphone)"
