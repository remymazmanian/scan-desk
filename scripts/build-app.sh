#!/bin/bash
# Builds Scanner.app from the Swift package and signs it.
#   scripts/build-app.sh            -> build/Scanner.app
#   scripts/build-app.sh --install  -> also copies it to ~/Applications
#   NOTARY_PROFILE=<profile> scripts/build-app.sh --notarize
#                                   -> also notarizes, staples, and writes build/Scanner.zip
#
# Signing: uses a "Developer ID Application" certificate from the keychain with the
# hardened runtime. Set SIGN_IDENTITY to a certificate's SHA-1 hash or name to choose
# one; with no Developer ID certificate it falls back to ad-hoc (this Mac only).
set -euo pipefail
INSTALL=0; NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --notarize) NOTARIZE=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
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

if [[ $NOTARIZE == 1 ]]; then
  [[ -n "$IDENTITY" ]] || { echo "Notarizing needs a Developer ID signature." >&2; exit 1; }
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials)}"
  # notarytool and stapler ship with Xcode, not the Command Line Tools.
  XCODE="/Applications/Xcode.app/Contents/Developer"
  [[ -d "$XCODE" ]] && export DEVELOPER_DIR="$XCODE"
  ZIP="$ROOT/build/Scanner.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"   # zip again, now with the ticket stapled
  echo "Notarized: $ZIP"
fi

if [[ $INSTALL == 1 ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Scanner.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/Scanner.app"
fi
