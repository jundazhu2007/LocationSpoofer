#!/bin/zsh
# Builds, signs, notarizes and packages a release.
#
# One-time setup (see README / CONTRIBUTING):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notarization credentials stored in the keychain:
#        xcrun notarytool store-credentials "LocationSpoofer" --apple-id <id> --team-id <TEAMID>
#      (it asks for an app-specific password; nothing is written to this repo)
#
# Usage:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#   Optional: VERSION=1.0.1  NOTARY_PROFILE=LocationSpoofer  UNIVERSAL=0 (arm64 only)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_ID:?Set SIGN_ID to your \"Developer ID Application: ...\" identity (security find-identity -v -p codesigning)}"
VERSION="${VERSION:-1.0.0}"
PROFILE="${NOTARY_PROFILE:-LocationSpoofer}"
export UNIVERSAL="${UNIVERSAL:-1}"       # releases are universal (Apple silicon + Intel) unless UNIVERSAL=0
ARCH_NAME="$([ "${UNIVERSAL:-0}" = "1" ] && echo universal || echo arm64)"
APP=LocationSpoofer.app
NAME="LocationSpoofer-$VERSION-macOS-$ARCH_NAME"
DIST=dist

rm -rf "$DIST"; mkdir -p "$DIST"
VERSION="$VERSION" SIGN_ID="$SIGN_ID" ./build_app.sh

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" >/dev/null \
  || { echo "App is not signed with a Developer ID identity and hardened runtime"; exit 1; }

echo "==> Submitting for notarization (this can take a few minutes)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/notarize.zip"
xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait
rm "$DIST/notarize.zip"

echo "==> Stapling the ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Gatekeeper assessment"
spctl -a -vvv -t exec "$APP"

echo "==> Disk image (signed, notarized, stapled)"
VERSION="$VERSION" SIGN_ID="$SIGN_ID" ./scripts/make_dmg.sh
xcrun notarytool submit "$DIST/$NAME.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DIST/$NAME.dmg"

echo "==> Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"
( cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "Done: $DIST/$NAME.dmg and $DIST/$NAME.zip"
