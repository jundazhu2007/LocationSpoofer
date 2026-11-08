#!/bin/zsh
# Builds both downloads for one release: Apple silicon and Intel (separate, native builds).
# Output in dist/: .dmg and .zip per architecture + SHA256SUMS.txt
#
#   ./scripts/build_all.sh            (ad-hoc signed; see release.sh for signed + notarized builds)
#   Optional: VERSION=1.0.0
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-1.0.0}"

rm -rf dist; mkdir -p dist
for ARCH in arm64 x86_64; do
  LABEL="$([ "$ARCH" = x86_64 ] && echo Intel || echo AppleSilicon)"
  echo "==> $LABEL ($ARCH)"
  ARCH=$ARCH ./build_app.sh | tail -1
  echo "    architecture: $(lipo -archs LocationSpoofer.app/Contents/MacOS/LocationSpoofer)"
  ARCH=$ARCH ./scripts/make_dmg.sh | tail -1
  ditto -c -k --sequesterRsrc --keepParent LocationSpoofer.app "dist/LocationSpoofer-$VERSION-$LABEL.zip"
done
( cd dist && shasum -a 256 *.dmg *.zip > SHA256SUMS.txt && cat SHA256SUMS.txt )
