#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
iconset="$PWD/dist/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Icons/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Icons/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$PWD/dist/AppIcon.icns"
