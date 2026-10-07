#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
zsh build.sh
zsh scripts/verify-artworks.sh
codesign --verify --deep --strict 'Starry Night.app'
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
archive="Starry-Night-$version-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent 'Starry Night.app' "dist/$archive"
cd dist
shasum -a 256 "$archive" > "$archive.sha256"
print "Packaged $archive"
