#!/usr/bin/env bash
# Builds a drag-to-Applications installer DMG for ZebraLabelPrint.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ZebraLabelPrint.app"
APP_PATH="$ROOT/build/DerivedData/Build/Products/Release/$APP_NAME"
STAGING="$ROOT/dist/dmg-staging"
TEMP_DMG="$ROOT/dist/temp.dmg"
OUTPUT_DMG="$ROOT/dist/ZebraLabelPrint-arm64.dmg"
BACKGROUND="$ROOT/scripts/dmg-background.png"
VOLNAME="Zebra Label Print"
WINDOW_BOUNDS="{100, 100, 660, 400}"
APP_ICON_X=160
APP_ICON_Y=180
APPLICATIONS_X=440
APPLICATIONS_Y=180

cd "$ROOT"
mkdir -p dist scripts

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release app not found. Building first…" >&2
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
  xcodebuild \
    -project ZebraLabelPrint.xcodeproj \
    -scheme ZebraLabelPrint \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    build
fi

if [[ ! -f "$BACKGROUND" ]]; then
  echo "Generating DMG background…" >&2
  FONT_BOLD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
  FONT_REG="/System/Library/Fonts/Supplemental/Arial.ttf"
  magick -size 660x400 \
    gradient:'#343438-#232326' \
    -gravity north \
    -pointsize 24 -fill '#e8e8ea' -font "$FONT_BOLD" \
    -annotate +0+36 'Zebra Label Print' \
    -gravity center \
    -pointsize 15 -fill '#a0a0a8' -font "$FONT_REG" \
    -annotate +0+20 'Drag to Applications to install' \
    "$BACKGROUND"
fi

echo "Preparing staging folder…" >&2
rm -rf "$STAGING" "$TEMP_DMG" "$OUTPUT_DMG"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating disk image…" >&2
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 200m \
  "$TEMP_DMG" >/dev/null

echo "Configuring Finder layout…" >&2
# shellcheck disable=SC2046
DEVICE=$(hdiutil attach -readwrite -noverify "$TEMP_DMG" | awk '/^\/dev\// {print $1; exit}')
MOUNT="/Volumes/$VOLNAME"

cleanup() {
  if [[ -n "${DEVICE:-}" ]]; then
    hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep 2
mkdir -p "$MOUNT/.background"
cp "$BACKGROUND" "$MOUNT/.background/background.png"

osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to $WINDOW_BOUNDS
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME" of container window to {$APP_ICON_X, $APP_ICON_Y}
    set position of item "Applications" of container window to {$APPLICATIONS_X, $APPLICATIONS_Y}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

chmod -Rf go-w "$MOUNT" || true
sync

hdiutil detach "$DEVICE" >/dev/null
DEVICE=""
trap - EXIT

echo "Compressing DMG…" >&2
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING"

echo "Done: $OUTPUT_DMG" >&2
ls -lh "$OUTPUT_DMG"
