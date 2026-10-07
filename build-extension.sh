#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
extension="$PWD/Starry Night.app/Contents/Extensions/StarryWallpaper.appex"
assets_dir="${STARRY_ASSETS_DIR:-$PWD/assets}"
movie="$assets_dir/starry-night-flow.mp4"
if [[ ! -f "$movie" ]]; then
  print -u2 "Missing $movie. Generate a loop from your licensed image first."
  exit 1
fi
mkdir -p "$extension/Contents/MacOS" "$extension/Contents/Resources" .module-cache
cp WallpaperExtension/Info.plist "$extension/Contents/Info.plist"
cp WallpaperExtension/PHOSPHENE-LICENSE.txt "$extension/Contents/Resources/"
cp "$movie" "$extension/Contents/Resources/wallpaper.mp4"
xcrun swiftc -O -swift-version 6 -parse-as-library -application-extension -module-name StarryWallpaper \
  -target arm64-apple-macos26.0 -module-cache-path "$PWD/.module-cache" \
  -import-objc-header WallpaperExtension/WallpaperExtension-Bridging-Header.h \
  -framework AppKit -framework AVFoundation -framework ExtensionFoundation \
  -framework QuartzCore -framework IOSurface -framework Security -framework IOKit \
  -Xlinker -e -Xlinker _EXExtensionMain -Xlinker -u -Xlinker _main \
  WallpaperExtension/*.swift -o "$extension/Contents/MacOS/StarryWallpaper"
codesign --force --sign - --options runtime --entitlements WallpaperExtension/Entitlements.plist "$extension"
