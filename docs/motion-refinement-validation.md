# Four existing wallpapers: refinement validation

This PR keeps the five-work collection and changes only Water Lilies, Wheat Stacks, Rhône and Cypresses. The Starry Night field, mask and sampling remain unchanged.

## Changes

- Water Lilies: closer lily contours, quieter horizontal pond ripples
- Wheat Stacks: zero geometric displacement; approximately ±0.45% luminance limited to existing warm sky pigments at default strength
- Rhône: depth-dependent river motion; close-fitting boat, mast, rigging and bank protection
- Cypresses: small tangent motion following painted cloud curls; wheat-tip sway with tree, olive foliage and mountain protection
- Motion paths are checked at midpoint and endpoint; a second original-image dissolve is removed to avoid soft double edges
- Wheat verification uses t=6/18, any RGB difference >0 and more than 1,000 changed pixels; the former blue-channel >2 test misses this deliberately subtle effect

## Checks performed

CPU reference expressions were extracted from the actual Metal source and compiled as C++; mask rasterization and feathering were approximated with Pillow. Each before/after comparison ran 720 frames at 30fps over 24 seconds, plus strength 0/1.4/2.5, speed 0.25/1/2 and selected 16:10/16:9/21:9 phase checks. Full protected regions and independent subject ROIs stayed unchanged in the post-refinement raw frames.

Maximum displacement at 768px panel width: Water Lilies 2.961→0.883px, Wheat 0.927→0px, Rhône 3.294→0.880px, Cypresses 4.483→0.611px. Native-sized Wheat t6/t18 CPU reference: 251,496 changed pixels, maximum RGB difference 3/255.

Shell syntax and git diff checks pass. This is **not** a native Swift/Metal build or an AppKit, AVFoundation, desktop or lock-screen test. CoreImage kernels, native image decoding and numeric precision may differ. Lossy preview videos cannot prove bit-exact subject protection and may obscure Wheat’s very weak light signal; raw reference frames are the pixel-level evidence.

On macOS, prepare the existing artwork assets and run `zsh build.sh`, `zsh scripts/verify-artworks.sh` and `zsh scripts/verify-gallery.sh`. No new wallpaper resource or collection item is introduced here.
