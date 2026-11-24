#!/bin/zsh
# Builds a signed + notarized OpenMirror.dmg ready for GitHub Releases.
#
# Requirements (one-time):
#   • "Developer ID Application" certificate in the login keychain
#   • xcrun notarytool store-credentials <profile> --apple-id <email> --team-id <TEAM>
#
# Usage: scripts/release.sh <TEAM_ID> [notary-profile=openmirror-notary]
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${1:?usage: scripts/release.sh <TEAM_ID> [notary-profile]}"
PROFILE="${2:-openmirror-notary}"
VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2}' project.yml)
IDENTITY="Developer ID Application"
OUT="build/release"
APP="$OUT/Build/Products/Release/OpenMirror.app"
DMG="$OUT/OpenMirror-$VERSION.dmg"

security find-identity -v -p codesigning | grep -q "$IDENTITY.*($TEAM_ID)" \
  || { echo "✗ No '$IDENTITY' certificate for team $TEAM_ID in the keychain"; exit 1; }

echo "▸ Building OpenMirror $VERSION (Release, hardened runtime)…"
rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen -q
xcodebuild build -project OpenMirror.xcodeproj -scheme OpenMirror -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$OUT" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" > "$OUT/build.log" 2>&1 \
  || { tail -20 "$OUT/build.log"; echo "✗ build failed (see $OUT/build.log)"; exit 1; }

codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" >/dev/null \
  || { echo "✗ app is not signed with Developer ID + hardened runtime"; exit 1; }

echo "▸ Creating disk image…"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "OpenMirror" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "▸ Notarizing (usually 1–5 min)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee "$OUT/notary.log"
grep -q "status: Accepted" "$OUT/notary.log" || { echo "✗ notarization was not accepted"; exit 1; }

xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "✓ $DMG"
