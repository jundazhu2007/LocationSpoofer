#!/bin/zsh
# Packages LocationSpoofer.app into a drag-to-install disk image (.dmg).
#
#   ./build_app.sh && ./scripts/make_dmg.sh
#   Optional: VERSION=1.0.0  UNIVERSAL=1 (only changes the file name)  SIGN_ID="Developer ID Application: ..."
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
ARCH_NAME="$([ "${UNIVERSAL:-0}" = "1" ] && echo universal || echo arm64)"
APP=LocationSpoofer.app
OUT="dist/LocationSpoofer-$VERSION-macOS-$ARCH_NAME.dmg"
[ -d "$APP" ] || { echo "Build the app first: ./build_app.sh"; exit 1; }

mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/LocationSpoofer.app"      # ditto keeps signatures and attributes intact
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/First launch.txt" <<'TXT'
Location Spoofer

1. Drag LocationSpoofer.app onto the Applications folder.
2. If macOS says it cannot verify the app (it is not notarized):
   - open System Settings > Privacy & Security and click "Open Anyway", or
   - run in Terminal:  xattr -dr com.apple.quarantine /Applications/LocationSpoofer.app

1. 把 LocationSpoofer.app 拖進「應用程式」資料夾。
2. 若 macOS 提示無法驗證(此版本尚未公證):
   - 到「系統設定 > 隱私權與安全性」按「仍要打開」,或
   - 在終端機執行:xattr -dr com.apple.quarantine /Applications/LocationSpoofer.app

1. LocationSpoofer.app を「アプリケーション」フォルダにドラッグします。
2. macOS が確認できないと表示した場合(公証されていません):
   - システム設定 > プライバシーとセキュリティで「このまま開く」をクリック、または
   - ターミナルで xattr -dr com.apple.quarantine /Applications/LocationSpoofer.app を実行

https://github.com/jundazhu2007/LocationSpoofer
TXT

rm -f "$OUT"
hdiutil create -volname "Location Spoofer" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
[ -n "${SIGN_ID:-}" ] && codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
hdiutil verify "$OUT" >/dev/null && echo "Created $OUT"
