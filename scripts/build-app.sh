#!/bin/bash
# Builds Scanner.app from the Swift package and signs it ad-hoc (local use only).
#   scripts/build-app.sh            -> build/Scanner.app
#   scripts/build-app.sh --install  -> also copies it to ~/Applications
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/App"
swift build -c release --product Scanner
BIN="$(swift build -c release --show-bin-path)/Scanner"

APP="$ROOT/build/Scanner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Scanner"
cp "$ROOT/App/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/App/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/App/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Scanner.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Scanner.app"
fi
