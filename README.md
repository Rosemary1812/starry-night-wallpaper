# Starry Night Wallpaper

An experimental macOS 26 wallpaper extension with a Metal control panel. It turns a supplied image and looping video into a dynamic wallpaper and lock-screen option.

This project uses private macOS APIs. It is for personal development and research. It is not suitable for the Mac App Store, is not notarized, and can stop working after a macOS update.

## Requirements

- Apple Silicon Mac running macOS 26.
- Xcode Command Line Tools.
- A legally usable image named `starrynight.jpg` and a looping video named `starry-night-flow.mp4`.

The repository does not include artwork or video. You must obtain or create assets that you have the right to use. Do not add them to Git.

## Build

1. Create `assets/`.
2. Put the image at `assets/starrynight.jpg`.
3. Put the video at `assets/starry-night-flow.mp4`.
4. Run `zsh build.sh`.

The build creates `Starry Night.app` in the repository. It signs the bundle with an ad hoc signature. The script does not install the app or change your wallpaper.

To keep assets elsewhere, set `STARRY_ASSETS_DIR` to the directory that contains both files before you run the build.

## Use

Open `Starry Night.app`, then select the "Starry Night" entry in **System Settings > Wallpaper**. macOS manages the extension after you select it. To stop using the extension, select another wallpaper.

## License and attribution

This repository is licensed under the MIT License. The files in `WallpaperExtension/` derive from [Phosphene](https://github.com/kageroumado/phosphene) at commit `8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6` and retain its MIT license. Read [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the local changes and limitations.
