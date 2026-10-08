# Native gallery and localization

The AppKit carousel uses one Metal preview for the settled selection. Adjacent
cards and all thumbnails use cached images. Dragging temporarily uses the still
fallback; the live preview becomes visible after its first completed frame.
The caption changes after settling, with a short fade when Reduce Motion is off.

`CarouselMotion` keeps a continuous position, velocity, and target. Release
projects recent velocity into a bounded page target, then uses a critically
damped spring. Retargeting preserves position and velocity. AppKit momentum
events do not compete with that spring. Reduce Motion snaps directly and disables
distance-based scaling. Arrow keys, side arrows, and thumbnails share this state.

At widths of 1000 points and above, the caption sits beside the painting with
the artist/year line aligned to its bottom. Below that breakpoint, it moves
underneath. The artwork title has its own line. Adjust, the accessible ellipsis
menu, and Set Wallpaper use regular native control sizes and intrinsic widths.
The metadata-to-controls gap is 24 points. The 12-point status has reserved space.

## Language, type, and state

Standard `en.lproj`, `zh-Hans.lproj`, and `zh-Hant.lproj` resources cover artwork
labels, motion descriptions, controls, menus, status, errors, and accessibility
labels. System language is the default. An explicit language choice persists
under the existing application's defaults domain. Verification overrides the
language only in memory and leaves the saved preference untouched.

The brand is exactly `StarryNight`. Bundle identifiers, artwork IDs, executable
and app directory names are unchanged. Source Serif 4 supplies the brand at
weight 500 and English titles at weight 400. Chinese titles use the installed
Songti SC or TC Regular font. Controls and metadata use the system font.
[Font sources, hashes and size](../Fonts/README.md) and the full OFL license are
included. Font registration is process-scoped, without installation or subsetting.

Browsing and applying are separate actions. The status distinguishes a preview,
unapplied changes, prepared video, and the provider selected in Wallpaper
Settings. Preview pause does not write the system wallpaper's pause preferences.
The first-use message directs the user to Wallpaper Settings when the extension
container has not been initialized; it does not promise automatic activation.

## Scope and integration

This branch starts at main `8f4c5bae15076f6a33466b648adde8eac1401c44` and retains
its five paintings. It has no runtime or Git dependency on PR #1, #2, or #3.
`Sky.metal`, painting masks, image crops, and render-validation samples are
unchanged. The renderer adds an optional completion callback and localized errors.

The local design preview was also exercised with twelve paintings using PR #2
`baa5012a2c3e226bf8a27a3ef0d0aa94e00872b6` and PR #1
`866c71bf8647414bf54324cd41bb7b97d64198ac`. Those painting and motion changes are
excluded from this PR. PR #3's authoring guidance was read without importing it.
After separately merging PR #2, preserve its appended artwork IDs and crops,
extend the three localization tables for the new catalog, and retain its
single-character shortcut mapping. The carousel and thumbnail rail use
`Artwork.allCases`, so the collection size is not fixed in their layout.

## Verification

Build the complete app and extension with `zsh build.sh`. On a Mac with the
licensed source assets, run `zsh scripts/verify-gallery.sh`. The checks include
75 pure motion assertions; AppKit scenes for every registered painting in all three languages;
three languages, wide/narrow windows, both appearances, the 999/1000-point
breakpoint, actual font names and glyph coverage; six adjustment panels;
slider updates and busy recovery; 210 simulated motion frames; and the actual
run-loop animation timer. The script also runs the existing five-artwork Metal
loop, movement, and protected-point checks.

The translation tables also cover PR #2's seven additional paintings. See
[twelve-painting localization integration](twelve-painting-localization.md) for
the dependency pins, catalog-count guard, and separate validation of the
five-painting base and twelve-painting integration.

Output stays in ignored `dist/`. To encode the 105 sampled motion frames:

```sh
xcrun swift -module-cache-path .module-cache scripts/make-image-sequence-gif.swift \
  dist/gallery-evidence/carousel.gif --fps=30 --max-pixels=720 \
  dist/gallery-evidence/motion-frames/*.png
```

The AppKit snapshots and sequence run offscreen. Synthetic events drive the
production handlers; this is not a physical-mouse or screen recording. Snapshots
use the still-image fallback because `cacheDisplay` does not capture the Metal
presentation layer. Inactive native buttons can differ from active-window colors.

The Mac was locked during the earlier Computer Use check. Physical mouse and
trackpad feel, Tab focus traversal, the visible Metal first-frame handoff, and
quit/relaunch language persistence remain unverified. Installing the extension,
applying a wallpaper, and desktop/lock-screen playback were not tested. No system
wallpaper or permission setting was changed.
