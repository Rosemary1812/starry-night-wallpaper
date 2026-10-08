# Third-party notices

## Interface font

The application bundles Adobe [Source Serif 4](https://github.com/adobe-fonts/source-serif),
version 4.005, as an unmodified variable OpenType font. Copyright © 2014–2023
Adobe, with Reserved Font Name “Source”. It is licensed under the SIL Open Font
License 1.1; the complete license is bundled at `Fonts/SourceSerif4-LICENSE.md`.
The brand uses weight 500, and English artwork titles use weight 400. Chinese
titles use macOS's installed regional Songti fonts, which are not redistributed.


## Artwork images

The additional artwork reproductions are downloaded by `scripts/fetch-artworks.sh`.
They are bundled in local builds and downloadable application packages, but are not tracked in Git.

- Claude Monet, *Water Lilies*, 1906, Art Institute of Chicago, 1933.1157. Museum CC0 image via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1933.1157_-_Art_Institute_of_Chicago.jpg).
- Claude Monet, *Stacks of Wheat (Sunset, Snow Effect)*, 1890–91, Art Institute of Chicago, 1922.431. Museum CC0 image via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Stacks_of_Wheat_(Sunset,_Snow_Effect)_-_1922.431_-_Art_Institute_of_Chicago.jpg).
- Vincent van Gogh, *Starry Night Over the Rhône*, 1888, Musée d'Orsay. Public domain reproduction via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Starry_Night_Over_the_Rhone.jpg).
- Vincent van Gogh, *Wheat Field with Cypresses*, 1889, The Metropolitan Museum of Art, 1993.132. [Public domain museum image](https://www.metmuseum.org/art/collection/search/436535).

## Wallpaper extension

The Swift files and bridging header in `WallpaperExtension/` are derived from
[Phosphene](https://github.com/kageroumado/phosphene), commit
`8b5bd57c1450eda74cf2ec6ceaae2e586cfdfcd6`, copyright (c) 2026 kageroumado,
licensed under the MIT License. The full license is included in
`WallpaperExtension/PHOSPHENE-LICENSE.txt` and both application bundles.

Local modifications: dedicated `local.starrynight.flow` namespace; Starry Night
resource seeding; a fixed library item; localized settings presentation; removal
of unrelated context-menu actions; live replacement of generated video and
snapshot invalidation; standalone command-line packaging and the ExtensionKit
service entry point. `StarrySeed.swift` is a local addition. No separate
Phosphene application is installed or required.

The native wallpaper extension uses private macOS APIs. Compatibility with
future macOS versions is not guaranteed. This local ad-hoc-signed build is not
notarized or intended as a generally distributable installer.
