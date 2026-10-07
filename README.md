# Starry Night Wallpaper

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

## Control panel

The panel lets you choose a painting and adjust flow speed and motion amplitude before applying a new loop. Wide screens crop the painting to fill the screen; the preview shows the same fill behavior.

![Starry Night control panel with speed and amplitude controls](docs/media/settings-panel.png)

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

Open `Starry Night.app`, choose a painting, and click **应用到桌面与锁屏** (Apply to Desktop and Lock Screen). In **System Settings > Wallpaper**, select **流动星夜**. Set the screen saver to use the same wallpaper for the lock-screen effect. Changing paintings or sliders updates only the preview until you apply again. The control panel is currently in Chinese.

You can also export an MP4 without changing the system wallpaper. Run `zsh scripts/verify-artworks.sh` to check loop endpoints, protected regions, and motion for all five paintings. Screenshots are written to `dist/evidence/`. These rendering checks do not test macOS lock-screen playback.

## License and attribution

This repository is licensed under the MIT License. The files in `WallpaperExtension/` derive from [Phosphene](https://github.com/kageroumado/phosphene) at commit `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6` and retain its MIT license. Read [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the local changes and limitations.
