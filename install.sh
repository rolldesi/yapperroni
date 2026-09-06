#!/usr/bin/env bash
# Yapperroni installer.
#   curl -fsSL https://raw.githubusercontent.com/rolldesi/yapperroni/main/install.sh | bash
#
# Downloading with curl means the files never get a com.apple.quarantine
# attribute, so Gatekeeper never assesses them. That is the whole trick: the
# app is self-signed, and a self-signed app that arrives through a browser is
# blocked, while the same app fetched here is not.
set -euo pipefail

REPO="rolldesi/yapperroni"
APP="/Applications/Yapperroni.app"
TARBALL="Yapperroni.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(uname -s)" = "Darwin" ] || { echo "!! macOS only"; exit 1; }
[ "$(uname -m)" = "arm64" ] || {
  echo "!! Apple Silicon only — this build has no Intel slice."; exit 1; }

echo "==> downloading"
curl -fsSL -o "$TMP/$TARBALL" \
  "https://github.com/$REPO/releases/latest/download/$TARBALL"

echo "==> installing to /Applications"
# A running copy cannot be replaced underneath itself.
osascript -e 'quit app "Yapperroni"' 2>/dev/null || true
rm -rf "$APP"
tar -xzf "$TMP/$TARBALL" -C /Applications

# Belt and braces: covers someone who downloaded the tarball in a browser and
# ran this script against it. A curl fetch leaves nothing for this to strip.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

codesign --verify --strict "$APP" || { echo "!! signature invalid"; exit 1; }

echo "==> launching"
open "$APP"
echo
echo "Installed. Yapperroni is a menu-bar app — look for the mic icon up top."
echo "It will ask for Microphone and Accessibility permission on first use."
