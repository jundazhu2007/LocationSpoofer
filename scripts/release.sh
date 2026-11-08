#!/bin/zsh
# Builds, signs, notarizes and packages a release: one version, two downloads
# (Apple silicon and Intel).
#
# One-time setup (see README / CONTRIBUTING):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notarization credentials stored in the keychain:
#        xcrun notarytool store-credentials "LocationSpoofer" --apple-id <id> --team-id <TEAMID>
#      (it asks for an app-specific password; nothing is written to this repo)
#
# Usage:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#   Optional: VERSION=1.0.1  NOTARY_PROFILE=LocationSpoofer
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_ID:?Set SIGN_ID to your \"Developer ID Application: ...\" identity (security find-identity -v -p codesigning)}"
export VERSION="${VERSION:-1.0.0}"
PROFILE="${NOTARY_PROFILE:-LocationSpoofer}"
APP=LocationSpoofer.app
DIST=dist

rm -rf "$DIST"; mkdir -p "$DIST"

for ARCH in arm64 x86_64; do
  LABEL="$([ "$ARCH" = x86_64 ] && echo Intel || echo AppleSilicon)"
  NAME="LocationSpoofer-$VERSION-$LABEL"
  echo; echo "################ $LABEL ($ARCH) ################"

  ARCH=$ARCH SIGN_ID="$SIGN_ID" ./build_app.sh

  echo "==> Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|flags=.*runtime" >/dev/null \
    || { echo "App is not signed with a Developer ID identity and hardened runtime"; exit 1; }

  echo "==> Submitting the app for notarization (this can take a few minutes)"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/notarize.zip"
  xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait
  rm "$DIST/notarize.zip"

  echo "==> Stapling the ticket"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"

  echo "==> Gatekeeper assessment"
  spctl -a -vvv -t exec "$APP"

  echo "==> Disk image (signed, notarized, stapled)"
  ARCH=$ARCH SIGN_ID="$SIGN_ID" ./scripts/make_dmg.sh
  xcrun notarytool submit "$DIST/$NAME.dmg" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DIST/$NAME.dmg"

  ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"
done

( cd "$DIST" && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "Done. Files in $DIST/"
