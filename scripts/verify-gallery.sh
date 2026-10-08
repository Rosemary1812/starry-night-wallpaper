#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
STARRY_SKIP_EXTENSION_BUILD=1 zsh build.sh
xcrun swiftc -module-cache-path "$PWD/.module-cache" CarouselMotion.swift scripts/verify-carousel-motion.swift -o "$PWD/.module-cache/verify-carousel-motion"
"$PWD/.module-cache/verify-carousel-motion"
"$PWD/Starry Night.app/Contents/MacOS/StarryNight" --ui-check "$PWD/dist/gallery-evidence"
zsh scripts/verify-artworks.sh
git diff --check
