#!/bin/bash
# Builds Scanner.app from the Swift package and signs it.
#   scripts/build-app.sh            -> build/Scanner.app
#   scripts/build-app.sh --install  -> also copies it to ~/Applications
#
# Signing: uses a "Developer ID Application" certificate from the keychain with the
# hardened runtime. Set SIGN_IDENTITY to a certificate's SHA-1 hash or name to choose
# one; with no Developer ID certificate it falls back to ad-hoc (this Mac only).
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

# Pick a signing identity by hash, so duplicate certificates with the same name don't clash.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk '/"Developer ID Application:/ { h = $2 } END { print h }')"
fi

if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP"
  echo "Signed with Developer ID ($(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application.*\)/\1/p' | head -1))"
else
  codesign --force --sign - --timestamp=none "$APP"
  echo "No Developer ID certificate found: signed ad-hoc (this Mac only)"
fi
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Scanner.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Scanner.app"
fi
