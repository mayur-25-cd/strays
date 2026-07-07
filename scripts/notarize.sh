#!/bin/bash
# Signs, notarizes, and staples Strays into a distributable dist/Strays.dmg.
#
# The app is notarized and stapled FIRST, then packaged into a DMG that is also
# notarized and stapled — so both the mounted DMG and the extracted app pass
# Gatekeeper offline, on first launch.
#
# One-time setup (needs an Apple Developer account):
#   1. Create a "Developer ID Application" cert (Xcode → Settings → Accounts, or
#      developer.apple.com). Confirm it's installed:
#        security find-identity -v -p codesigning
#   2. Store notarization credentials in the keychain once:
#        xcrun notarytool store-credentials strays-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" \
#          --password "app-specific-password"   # appleid.apple.com → App-Specific Passwords
#
# Then run:
#   DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" ./scripts/notarize.sh
#
# Optional env: NOTARY_PROFILE (default: strays-notary)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your 'Developer ID Application: Name (TEAMID)' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-strays-notary}"
APP="dist/Strays.app"
DMG="dist/Strays.dmg"
ZIP="dist/Strays-notarize.zip"

echo "› Building release bundle…"
./scripts/build-app.sh release

echo "› Signing app with Developer ID + hardened runtime…"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "› Notarizing the app (this can take a few minutes)…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "› Building DMG from the stapled app…"
rm -f "$DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Strays" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "› Signing + notarizing the DMG…"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo ""
echo "✓ Notarized + stapled: $DMG"
echo "  sha256 (for the Homebrew cask):"
shasum -a 256 "$DMG" | awk '{print "  "$1}'
