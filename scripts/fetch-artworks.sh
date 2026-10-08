#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
assets_dir="${STARRY_ASSETS_DIR:-$PWD/assets}"
mkdir -p "$assets_dir"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/6/65/Claude_Monet_-_Water_Lilies_-_1933.1157_-_Art_Institute_of_Chicago.jpg' -o "$assets_dir/water-lilies.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/4/40/Claude_Monet_-_Stacks_of_Wheat_%28Sunset%2C_Snow_Effect%29_-_1922.431_-_Art_Institute_of_Chicago.jpg' -o "$assets_dir/wheat-stacks.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/9/94/Starry_Night_Over_the_Rhone.jpg' -o "$assets_dir/rhone.jpg"
curl -fL --retry 2 'https://images.metmuseum.org/CRDImages/ep/original/DP-42549-001.jpg' -o "$assets_dir/cypresses.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/5/59/Monet_-_Impression%2C_Sunrise.jpg' -o "$assets_dir/impression-sunrise.jpg"
# Additional collection; see THIRD-PARTY-NOTICES.md for artwork-specific rights.
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/d/d4/Monet_-_Waterloo_Bridge%2C_Sunlight_Effect%2C_1903.jpg' -o "$assets_dir/waterloo-bridge.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/8/86/Whistler_-_Nocturne_Blue_and_Silver--Bognor_%281871-1876%29.jpg' -o "$assets_dir/nocturne-bognor.jpg"
curl -fL --retry 2 'https://api.nga.gov/iiif/4f117b4f-4efe-4b2e-88e7-a01975003d95/full/full/0/default.jpg?attachment_filename=approach_to_venice_1937.1.110.jpg' -o "$assets_dir/approach-venice.jpg"
curl -fL --retry 2 'https://upload.wikimedia.org/wikipedia/commons/a/a4/Claude_Monet_-_Cliff_Walk_at_Pourville_-_Google_Art_Project.jpg' -o "$assets_dir/cliff-walk.jpg"
curl -fL --retry 2 'https://collectionapi.metmuseum.org/api/collection/v1/iiif/437680/1859178/main-image' -o "$assets_dir/bridge-villeneuve.jpg"
curl -fL --retry 2 'https://api.nga.gov/iiif/9eae6258-ec1c-442f-b353-a89cff510113/full/full/0/default.jpg?attachment_filename=the_houses_of_parliament_sunset_1963.10.48.jpg' -o "$assets_dir/parliament-sunset.jpg"
