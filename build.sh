#!/bin/bash
# Builds Knock.app into ./dist. Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${CONFIG:-release}"
APP="dist/Knock.app"

echo "▸ compiling ($CONFIG)…"
swift build -c "$CONFIG" --disable-sandbox

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Knock"

echo "▸ assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Knock"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signing keeps the Accessibility grant stable across rebuilds; without a
# stable identity macOS re-asks every time the binary changes.
echo "▸ signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ built $APP"

if [ "${1:-}" = "--run" ]; then
  echo "▸ launching…"
  pkill -x Knock 2>/dev/null || true
  sleep 0.4
  open "$APP"
fi
