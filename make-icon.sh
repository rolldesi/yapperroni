#!/usr/bin/env bash
set -euo pipefail

# Turns assets/icon.png into assets/Yapperroni.icns.
#
# To use your own logo: replace assets/icon.png with a square PNG (1024x1024
# is ideal) and run ./build.sh — it calls this automatically when the source
# image is newer than the built .icns.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/assets/icon.png"
OUT="$ROOT/assets/Yapperroni.icns"
SET="$(mktemp -d)/Yapperroni.iconset"
trap 'rm -rf "$(dirname "$SET")"' EXIT

[ -f "$SRC" ] || { echo "!! $SRC not found"; exit 1; }

W=$(sips -g pixelWidth  "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
if [ "$W" != "$H" ]; then
  echo "!! icon.png must be square (got ${W}x${H}) — macOS will squash it otherwise"
  exit 1
fi

mkdir -p "$SET"
for sz in 16 32 128 256 512; do
  sips -z $sz          $sz          "$SRC" --out "$SET/icon_${sz}x${sz}.png"     >/dev/null
  sips -z $((sz*2))    $((sz*2))    "$SRC" --out "$SET/icon_${sz}x${sz}@2x.png"  >/dev/null
done

iconutil -c icns "$SET" -o "$OUT"
echo "icon: $OUT"
