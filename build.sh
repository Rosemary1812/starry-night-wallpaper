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
zsh scripts/build-icon.sh
cp dist/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Resources/Fonts"
cp Fonts/SourceSerif4Variable-Roman.otf Fonts/SourceSerif4-LICENSE.md "$app/Contents/Resources/Fonts/"
for lproj in en.lproj zh-Hans.lproj zh-Hant.lproj; do
  rm -rf "$app/Contents/Resources/$lproj"
  cp -R "$lproj" "$app/Contents/Resources/$lproj"
done
cp "$painting" "$app/Contents/Resources/starrynight.jpg"
for artwork in water-lilies wheat-stacks rhone cypresses impression-sunrise waterloo-bridge nocturne-bognor approach-venice cliff-walk bridge-villeneuve parliament-sunset; do
  cp "$assets_dir/$artwork.jpg" "$app/Contents/Resources/$artwork.jpg"
done
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.module-cache" \
  -framework AppKit -framework Metal -framework MetalKit -framework CoreImage \
  -framework AVFoundation -framework UniformTypeIdentifiers \
  L10n.swift AppTypography.swift Artwork.swift CarouselMotion.swift GalleryView.swift GalleryVerification.swift StarryNight.swift WallpaperBridge.swift -o "$app/Contents/MacOS/StarryNight"
if [[ "${STARRY_SKIP_EXTENSION_BUILD:-0}" != 1 ]]; then zsh build-extension.sh; fi
cp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/"
cp WallpaperExtension/PHOSPHENE-LICENSE.txt "$app/Contents/Resources/"
codesign --force --sign - "$app"
printf '%s\n' "$app"
