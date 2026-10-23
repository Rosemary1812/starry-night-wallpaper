#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.module-cache" \
  LyricsCore.swift Tests/LyricsCoreTests.swift -o "$PWD/.module-cache/verify-lyrics"
"$PWD/.module-cache/verify-lyrics"
