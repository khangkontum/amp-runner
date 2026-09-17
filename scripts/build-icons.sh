#!/bin/bash
# Optional asset regeneration; requires librsvg (brew install librsvg).
# Generated PDF and ICNS are checked in, so normal app builds don't need it.
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir "$TEMP/AppIcon.iconset"
for SIZE in 16 32 128 256 512; do
    rsvg-convert -w "$SIZE" -h "$SIZE" "$ROOT/Resources/AppIcon.svg" -o "$TEMP/AppIcon.iconset/icon_${SIZE}x${SIZE}.png"
    rsvg-convert -w "$((SIZE * 2))" -h "$((SIZE * 2))" "$ROOT/Resources/AppIcon.svg" -o "$TEMP/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png"
done
iconutil -c icns "$TEMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
rsvg-convert -f pdf "$ROOT/Resources/AmpRunnerMenu.svg" -o "$ROOT/Resources/AmpRunnerMenu.pdf"
