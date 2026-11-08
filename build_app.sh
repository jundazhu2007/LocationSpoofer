#!/bin/zsh
# 建置 LocationSpoofer.app(release)。用法: ./build_app.sh
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
APP=LocationSpoofer.app

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LocationSpoofer "$APP/Contents/MacOS/"
cp -R Resources/* "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Location Spoofer</string>
  <key>CFBundleDisplayName</key><string>Location Spoofer</string>
  <key>CFBundleIdentifier</key><string>io.github.locationspoofer</string>
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

codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
