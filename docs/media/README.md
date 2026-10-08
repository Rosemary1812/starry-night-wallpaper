# README media

These GIFs were captured from the integrated source's production `Engine` and `Sky.metal`. They show native Metal output, not browser approximations or macOS desktop/lock-screen recordings.

## Recreate the GIFs

Build `Starry Night.app` with all twelve images, install Pillow in your Python environment, and run from the repository root:

```sh
python3 -m pip install Pillow
zsh scripts/record-readme-media.sh
```

Use `STARRY_PYTHON=/path/to/python` if Pillow is installed in a different interpreter. This interpreter is used for both renderer extraction and GIF encoding.

The script extracts the production `Engine` from `StarryNight.swift`, compiles it with `Artwork.swift` and `L10n.swift`, and uses the application's bundled images and Metal shader. Rebuild the app after a shader or asset change before recording.

Capture uses speed 1×, intensity 140%, a 24-second period, and 96 frames at 4 fps. Output uses a 16:10 aspect-fill crop, matching a 16:10 wallpaper rather than stretching the paintings. The native renderer checks that frames at 0 and 24 seconds match exactly for every painting before recording.

GIF encoding uses a fixed palette throughout each loop and no dithering to avoid introducing flicker into still subjects. Every GIF is checked for an infinite loop, a total duration of 24 seconds, and changed pixels during playback. Source frames, first-frame PNGs, and `capture.json` are written to ignored `dist/readme-media/`. Raw BGRA recordings are removed after successful encoding.

| File | Dimensions | Content |
| --- | --- | --- |
| `starry-night-preview.gif` | 480 × 300 | The Starry Night. |
| `water-lilies.gif` | 400 × 250 | Water Lilies. |
| `wheat-stacks.gif` | 400 × 250 | Stacks of Wheat, local brightness changes only. |
| `rhone.gif` | 400 × 250 | Starry Night over the Rhône. |
| `cypresses.gif` | 400 × 250 | Wheat Field with Cypresses. |
| `painting-collection.gif` | 690 × 412 | All twelve paintings, in the app's order, with synchronized loop times. |

The individual GIFs use up to 128 colors. The collection uses up to 64 colors to keep the download small. GIFs are reduced documentation previews; the app exports 30 fps H.264 video at higher resolution.

## Artwork attribution

Painting images and derivatives retain the terms in [THIRD-PARTY-NOTICES.md](../../THIRD-PARTY-NOTICES.md). The paintings' names and order are listed in both project READMEs.

`painting-collection.gif` includes a resized, aspect-filled, animated derivative of Claude Monet's *Waterloo Bridge, Sunlight Effect*, 1903. Credit: Claude Monet / Art Institute of Chicago, via [Wikimedia Commons uploader Maltaper](https://commons.wikimedia.org/wiki/File:Monet_-_Waterloo_Bridge,_Sunlight_Effect,_1903.jpg). This combined GIF is distributed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Changes include resizing, layout with other paintings and captions, aspect-fill cropping, and masked motion. The code's MIT declaration does not replace this media license.

`readme-header.png` is an AI-assisted editorial layout using the local reproduction of Vincent van Gogh's *The Starry Night*, 1889, as its reference. It is a documentation graphic, not a screenshot or a faithful reproduction of the original painting. The app icon uses a broader monochrome crop of the same painting with the stars removed. A [public-domain reproduction and painting metadata](https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg) are available on Wikimedia Commons.
