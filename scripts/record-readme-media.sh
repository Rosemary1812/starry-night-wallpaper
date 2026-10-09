#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
python="${STARRY_PYTHON:-python3}"
output="$PWD/dist/readme-media"
mkdir -p "$output" "$PWD/.module-cache"
cmp Sky.metal "$PWD/Starry Night.app/Contents/Resources/Sky.metal"
# Extract the production renderer without the application's entry point.
"$python" - "$output/Engine.swift" <<'PY'
from pathlib import Path
import sys
source = Path('StarryNight.swift').read_text()
Path(sys.argv[1]).write_text(source.split('final class AnimationState {', 1)[0])
PY
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/.module-cache" \
  -framework AppKit -framework Metal -framework MetalKit -framework CoreImage \
  -framework AVFoundation -framework UniformTypeIdentifiers \
  L10n.swift Artwork.swift "$output/Engine.swift" scripts/record-readme-media.swift \
  -o "$output/record"
"$output/record" "$PWD/Starry Night.app/Contents/Resources" "$output"
"$python" scripts/encode-readme-media.py
