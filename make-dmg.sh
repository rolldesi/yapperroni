#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/Yapperroni.app"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Always build first. Packaging whatever happens to be sitting in
# ~/Applications is how a stale binary gets shipped.
echo "==> building from current sources"
"$ROOT/build.sh" >/dev/null || { echo "!! build failed"; exit 1; }

# A DMG whose app has a broken seal fails to launch with no useful error, so
# refuse to ship one rather than find out later.
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$ROOT/dist/Yapperroni-$VERSION.dmg"

echo "==> verifying signature"
if ! codesign --verify --strict "$APP" 2>&1; then
  echo "!! signature invalid — run ./build.sh again"
  exit 1
fi

if [ ! -f "$APP/Contents/Resources/ggml-small.en-q5_1.bin" ]; then
  echo "!! no model inside the bundle — rebuild without YAPPERRONI_SKIP_MODEL=1"
  exit 1
fi

echo "==> staging"
mkdir -p "$ROOT/dist"
cp -R "$APP" "$STAGE/Yapperroni.app"
ln -s /Applications "$STAGE/Applications"

echo "==> building $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Yapperroni" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo
echo "built: $DMG  ($(du -h "$DMG" | cut -f1))"
echo
echo "Install: open the DMG, drag Yapperroni to Applications."
echo "Yapperroni is a menu-bar app — look for the mic icon in the menu bar, not the Dock."
echo
echo "This is self-signed, not notarized. It launches fine on this Mac."
echo "On someone else's Mac, after a download, Gatekeeper will block it —"
echo "that needs a \$99 Apple Developer ID and notarization, not a packaging change."
