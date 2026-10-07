#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
assets_dir="${STARRY_ASSETS_DIR:-$PWD/assets}"
mkdir -p "$assets_dir"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/6/65/Claude_Monet_-_Water_Lilies_-_1933.1157_-_Art_Institute_of_Chicago.jpg' -o "$assets_dir/water-lilies.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/4/40/Claude_Monet_-_Stacks_of_Wheat_%28Sunset%2C_Snow_Effect%29_-_1922.431_-_Art_Institute_of_Chicago.jpg' -o "$assets_dir/wheat-stacks.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/9/94/Starry_Night_Over_the_Rhone.jpg' -o "$assets_dir/rhone.jpg"
curl -fL --retry 2 'https://images.metmuseum.org/CRDImages/ep/original/DP-42549-001.jpg' -o "$assets_dir/cypresses.jpg"
