# StarryNight

[简体中文](README.zh-CN.md)

An experimental macOS 26 dynamic wallpaper extension with a Metal control panel. Choose a painting, adjust its motion, and render a looping video for the desktop and lock screen.

![Animated Starry Night preview](docs/media/starry-night-preview.gif)

## Painting collection

The collection includes Van Gogh's *The Starry Night* and four more paintings. Motion is deliberately subtle; masks protect the main subjects.

### Monet — Water Lilies (1906)

Water and reflections ripple gently; the main lily clusters stay still.

![Water Lilies animated preview](docs/media/water-lilies.gif)

### Monet — Stacks of Wheat (Sunset, Snow Effect) (1890–91)

The sky shifts and the sunset light breathes gently; the stacks and snow remain still.

![Stacks of Wheat animated preview](docs/media/wheat-stacks.gif)

### Van Gogh — Starry Night over the Rhône (1888)

The river and reflected lights shimmer; the shoreline, boat mast, and foreground figures remain still.

![Starry Night over the Rhône animated preview](docs/media/rhone.gif)

### Van Gogh — Wheat Field with Cypresses (1889)

Clouds and wheat move gently; the main cypress and middle hills remain still.

![Wheat Field with Cypresses animated preview](docs/media/cypresses.gif)

## Gallery control panel

The native AppKit gallery centers and scales the selected painting, with adjacent
paintings visible beside it. Only the selected painting uses the Metal preview;
neighboring cards and the thumbnail strip use cached still images. Drag, use the
arrow keys, or select a thumbnail. The caption updates after selection settles.

A wide window places the artwork title and artist/year beside the painting. In a
narrow window they move below it. The action row contains **Adjust…**, an ellipsis
menu, and **Set Wallpaper**. Speed, intensity, preview pause, the diagnostic mask,
and language are in Adjustments. Export, artwork details, sources, licenses, and
Wallpaper Settings are in the ellipsis menu.

The interface follows the system language by default, with persistent choices
for Simplified Chinese, Traditional Chinese, and English. It follows light/dark
appearance and Reduce Motion. The brand remains **StarryNight** in every language.
See [native gallery implementation and verification](docs/native-gallery.md).

The downloadable v0.2.0 app still has the earlier control panel.

## Download

Download from [GitHub Releases](https://github.com/Rosemary1812/starry-night-wallpaper/releases) for Apple Silicon Macs running macOS 26. Release packages include a ZIP archive and a SHA-256 checksum. The original v0.1.0 contains only The Starry Night.

This build uses private macOS APIs. It is not notarized and is not suitable for the Mac App Store. macOS may require you to Control-click the app in Finder and select **Open**. A future macOS update can stop the extension from working.

## Build from source

You need an Apple Silicon Mac running macOS 26, Xcode Command Line Tools, a legally usable image, and a looping video.

1. Create `assets/`.
2. Put the image at `assets/starrynight.jpg`.
3. Put the video at `assets/starry-night-flow.mp4`.
4. Run `zsh scripts/fetch-artworks.sh` to download the four additional public-domain reproductions.
5. Run `zsh build.sh`.

The build creates `Starry Night.app` in the repository and signs it with an ad hoc signature. It does not install the app or change your wallpaper. To keep assets elsewhere, set `STARRY_ASSETS_DIR` to the directory that contains all image and video assets before downloading and building.

The repository does not include the full-size source image or video that the build needs. The documentation media is a reduced-size preview only. Use assets that you have the right to distribute.

## Use

Open `Starry Night.app` and choose a painting. Command-1 through Command-5 also
select paintings. In **Adjust…**, change speed and intensity or pause the preview.
Preview pause affects only this window. It does not pause the system wallpaper.
The language menu includes **Follow System** and the three explicit languages.

**Set Wallpaper** prepares and publishes a loop for the selected painting. You
may need to select **StarryNight** in **System Settings > Wallpaper**. First use
can require opening Wallpaper Settings so macOS initializes the extension. The
status distinguishes preview-only, unapplied changes, prepared output, and a
provider selected in System Settings. It does not confirm lock-screen playback.
Changing the painting or sliders updates only the preview until you apply again.

Wide screens crop the painting to fill the screen. **Show motion mask** temporarily
highlights animated preview regions. **Export Video…** saves an MP4 without changing
the system wallpaper.

## Verify the source build

Run `zsh scripts/verify-gallery.sh` on a Mac with the required assets. It rebuilds
the control panel, runs 75 motion assertions, checks the three languages at wide
and narrow sizes in both appearances, checks all five paintings, and verifies
slider updates and busy-state recovery. It also checks reduced motion and the
production animation timer. Six adjustment panels are checked separately.
Screenshots and layout data are written to `dist/gallery-evidence/`.

The UI check runs offscreen without applying wallpaper or changing saved preview
parameters. The continuous sequence uses synthetic AppKit events; it is not a
physical-mouse recording. Its snapshots use the static fallback because
`cacheDisplay` does not capture Metal presentation layers. Interactive focus,
trackpad feel, and the live first-frame handoff still need a visible-window check.

The script also runs `scripts/verify-artworks.sh` to check loop endpoints,
protected-subject samples, and motion for all five paintings. Rendering snapshots
are written to `dist/evidence/`. These checks do not test lock-screen playback.

## License and attribution

This repository is licensed under the MIT License. The files in `WallpaperExtension/` derive from [Phosphene](https://github.com/kageroumado/phosphene) at commit `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6` and retain its MIT license. Read [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the local changes and limitations.
