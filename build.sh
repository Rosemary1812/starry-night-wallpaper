#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app="$PWD/Starry Night.app"
assets_dir="${STARRY_ASSETS_DIR:-$PWD/assets}"
painting="$assets_dir/starrynight.jpg"
if [[ ! -f "$painting" ]]; then
  print -u2 "Missing $painting. Put a legally usable image there or set STARRY_ASSETS_DIR."
  exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$PWD/.module-cache"
cp Info.plist "$app/Contents/Info.plist"
cp Sky.metal "$app/Contents/Resources/Sky.metal"
cp "$painting" "$app/Contents/Resources/starrynight.jpg"
for artwork in water-lilies wheat-stacks rhone cypresses; do
  cp "$assets_dir/$artwork.jpg" "$app/Contents/Resources/$artwork.jpg"
done
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.module-cache" \
  -framework AppKit -framework Metal -framework MetalKit -framework CoreImage \
  -framework AVFoundation -framework UniformTypeIdentifiers \
  Artwork.swift GalleryView.swift GalleryVerification.swift StarryNight.swift WallpaperBridge.swift -o "$app/Contents/MacOS/StarryNight"
if [[ "${STARRY_SKIP_EXTENSION_BUILD:-0}" != 1 ]]; then zsh build-extension.sh; fi
cp WallpaperExtension/PHOSPHENE-LICENSE.txt "$app/Contents/Resources/"
codesign --force --sign - "$app"
printf '%s\n' "$app"
