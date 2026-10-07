#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
app="$PWD/Starry Night.app/Contents/MacOS/StarryNight"
mkdir -p dist/evidence
for artwork in starrynight water-lilies wheat-stacks rhone cypresses; do
  "$app" --verify --artwork "$artwork"
  "$app" --snapshot "$PWD/dist/evidence/$artwork.png" 8 --artwork "$artwork"
  "$app" --snapshot "$PWD/dist/evidence/$artwork-mask.png" 8 --artwork "$artwork" --mask
done
