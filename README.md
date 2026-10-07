# Starry Night Wallpaper

[简体中文](README.zh-CN.md)

An experimental macOS 26 dynamic wallpaper extension with a Metal control panel. It animates a user-supplied image and looping video for the desktop and lock screen.

![Animated Starry Night preview](docs/media/starry-night-preview.gif)

## Control panel

The panel lets you adjust the flow speed and rotation amplitude before you apply a new loop to the wallpaper.

![Starry Night control panel with speed and amplitude controls](docs/media/settings-panel.png)

## Download

Download [Starry Night v0.1.0](https://github.com/Rosemary1812/starry-night-wallpaper/releases/tag/v0.1.0) for Apple Silicon Macs running macOS 26. The release includes a ZIP archive and a SHA-256 checksum.

This build uses private macOS APIs. It is not notarized and is not suitable for the Mac App Store. macOS may require you to Control-click the app in Finder and select **Open**. A future macOS update can stop the extension from working.

## Build from source

You need an Apple Silicon Mac running macOS 26, Xcode Command Line Tools, a legally usable image, and a looping video.

1. Create `assets/`.
2. Put the image at `assets/starrynight.jpg`.
3. Put the video at `assets/starry-night-flow.mp4`.
4. Run `zsh build.sh`.

The build creates `Starry Night.app` in the repository and signs it with an ad hoc signature. It does not install the app or change your wallpaper. To keep assets elsewhere, set `STARRY_ASSETS_DIR` to the directory that contains both files before you run the build.

The repository does not include the full-size source image or video that the build needs. The documentation media is a reduced-size preview only. Use assets that you have the right to distribute.

## Use

Open `Starry Night.app`, then select the "Starry Night" entry in **System Settings > Wallpaper**. macOS manages the extension after you select it. To stop using the extension, select another wallpaper.

## License and attribution

This repository is licensed under the MIT License. The files in `WallpaperExtension/` derive from [Phosphene](https://github.com/kageroumado/phosphene) at commit `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6` and retain its MIT license. Read [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the local changes and limitations.
