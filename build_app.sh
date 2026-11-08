#!/bin/zsh
# Builds LocationSpoofer.app (release).
#
#   ./build_app.sh                       ad-hoc signed (fine for local use)
#   VERSION=1.2.3 ./build_app.sh         set the version
#   SIGN_ID="Developer ID Application: Name (TEAMID)" ./build_app.sh
#                                        sign for distribution (hardened runtime + secure timestamp)
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
APP=LocationSpoofer.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LocationSpoofer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp -R Resources/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Location Spoofer</string>
  <key>CFBundleDisplayName</key><string>Location Spoofer</string>
  <key>CFBundleIdentifier</key><string>io.github.jundazhu2007.LocationSpoofer</string>
  <key>CFBundleExecutable</key><string>LocationSpoofer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hant</string><string>en</string><string>ja</string></array>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Jundazhu · MIT License</string>
</dict></plist>
PL

if [ -n "${SIGN_ID:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP ($VERSION)"
