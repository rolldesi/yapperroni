#!/usr/bin/env bash
# Cut a GitHub release that install.sh can pull from.
# Uploads a tarball of the built app; make-dmg.sh still owns the .dmg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${YAPPERRONI_INSTALL_DIR:-/Applications}/Yapperroni.app"

echo "==> building from current sources"
"$ROOT/build.sh" >/dev/null || { echo "!! build failed"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
TAR="$ROOT/dist/Yapperroni.tar.gz"

echo "==> verifying signature"
codesign --verify --strict "$APP" || { echo "!! signature invalid"; exit 1; }
[ -f "$APP/Contents/Resources/ggml-small.en-q5_1.bin" ] || {
  echo "!! no model inside the bundle"; exit 1; }

# -H follows no symlinks but stores them as symlinks, which the bundle needs.
echo "==> archiving"
mkdir -p "$ROOT/dist"
tar -czf "$TAR" -C "$(dirname "$APP")" Yapperroni.app

echo "==> publishing v$VERSION"
gh release view "v$VERSION" >/dev/null 2>&1 \
  && gh release upload "v$VERSION" "$TAR" --clobber \
  || gh release create "v$VERSION" "$TAR" \
       --title "Yapperroni $VERSION" \
       --notes "Install: \`curl -fsSL https://raw.githubusercontent.com/rolldesi/yapperroni/main/install.sh | bash\`"

echo
echo "Released v$VERSION ($(du -h "$TAR" | cut -f1))."
echo "Send this line:"
echo "  curl -fsSL https://raw.githubusercontent.com/rolldesi/yapperroni/main/install.sh | bash"
