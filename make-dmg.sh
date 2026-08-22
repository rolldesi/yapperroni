#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${YAPPERRONI_INSTALL_DIR:-/Applications}/Yapperroni.app"
VOL="Yapperroni"
STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"

cleanup() {
  hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
  rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

# Always build first. Packaging whatever happens to be sitting in the install
# directory is how a stale binary gets shipped.
echo "==> building from current sources"
"$ROOT/build.sh" >/dev/null || { echo "!! build failed"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$ROOT/dist/Yapperroni-$VERSION.dmg"

echo "==> verifying signature"
codesign --verify --strict "$APP" || { echo "!! signature invalid"; exit 1; }
[ -f "$APP/Contents/Resources/ggml-small.en-q5_1.bin" ] || {
  echo "!! no model inside the bundle"; exit 1; }

# A volume from an interrupted earlier run would break the Finder scripting.
hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true

echo "==> staging"
mkdir -p "$ROOT/dist" "$STAGE/.background"
cp -R "$APP" "$STAGE/Yapperroni.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/assets/dmg-bg.tiff" "$STAGE/.background/bg.tiff"
[ -f "$ROOT/assets/Yapperroni.icns" ] && cp "$ROOT/assets/Yapperroni.icns" "$STAGE/.VolumeIcon.icns"

# Read-write image first: the Finder layout has to be written into the volume
# before it is compressed and sealed read-only.
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 80 ))
echo "==> creating writable image (${SIZE_MB}MB)"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
  -format UDRW -size "${SIZE_MB}m" "$RW" >/dev/null

echo "==> applying window layout"
hdiutil attach "$RW" -noautoopen -quiet
sleep 1

osascript <<'AS' >/dev/null 2>&1 || echo "    (Finder styling skipped — needs a GUI session)"
tell application "Finder"
  tell disk "Yapperroni"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- {left, top, right, bottom}: a 660x420 content area
    set the bounds of container window to {200, 120, 860, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:bg.tiff"
    set position of item "Yapperroni.app" of container window to {165, 195}
    set position of item "Applications" of container window to {495, 195}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
AS

# Custom volume icon, so the mounted disk shows the app mark.
if [ -f "/Volumes/$VOL/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "/Volumes/$VOL"
fi

sync
hdiutil detach "/Volumes/$VOL" -quiet
sleep 1

echo "==> compressing"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo
echo "built: $DMG  ($(du -h "$DMG" | cut -f1))"
echo
echo "Open it and drag Yapperroni into Applications."
echo "It is a menu-bar app: after launching, look for the mic icon in the menu bar."
echo
echo "Self-signed, not notarized. Launches fine on this Mac; on someone else's,"
echo "after a download, Gatekeeper blocks it until it is notarized."
