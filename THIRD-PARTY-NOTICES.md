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

- Claude Monet, *Impression, Sunrise (Impression, soleil levant)*, 1872, Musée Marmottan Monet. Faithful public-domain reproduction, marked PDM 1.0 on [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Monet_-_Impression,_Sunrise.jpg). The download uses the 5773 × 4478 `Monet - Impression, Sunrise.jpg` image; its full composition is preserved before the existing aspect-fill screen crop.

## Additional collection images

- Claude Monet, *Waterloo Bridge, Sunlight Effect*, 1903, Art Institute of Chicago, 1933.1163. Credit: Claude Monet / Art Institute of Chicago, via [Wikimedia Commons, uploader Maltaper](https://commons.wikimedia.org/wiki/File:Monet_-_Waterloo_Bridge,_Sunlight_Effect,_1903.jpg). The specific reproduction is [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), not covered by the repository's MIT license. Resized/cropped previews and animated derivatives of this image are also provided under CC BY-SA 4.0, with changes consisting of resizing, aspect-fill cropping where selected, masked motion, and the optional diagnostic overlay. Retain this attribution and license when redistributing that image or its derivatives. The source image itself is stored unchanged.
- James McNeill Whistler, *Nocturne: Blue and Silver—Bognor*, 1871–1876, Freer Gallery of Art, Smithsonian, Gift of Charles Lang Freer, F1906.103a-b. [Official CC0/open-access record](https://www.si.edu/object/nocturne-blue-and-silver-bognor%3Afsg_F1906.103a-b); public-domain reproduction via [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Whistler_-_Nocturne_Blue_and_Silver--Bognor_(1871-1876).jpg).
- J. M. W. Turner, *Approach to Venice*, 1844, National Gallery of Art, Andrew W. Mellon Collection, 1937.1.110. [Public-domain museum image](https://www.nga.gov/artworks/117-approach-venice).
- Claude Monet, *Cliff Walk at Pourville*, 1882, Art Institute of Chicago, 1933.443. Public-domain reproduction via [Google Art Project / Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Cliff_Walk_at_Pourville_-_Google_Art_Project.jpg); [museum catalogue](https://publications.artic.edu/node/135468).
- Alfred Sisley, *The Bridge at Villeneuve-la-Garenne*, 1872, The Metropolitan Museum of Art, Gift of Mr. and Mrs. Henry Ittleson Jr., 1964, 64.287. [Public-domain museum image](https://www.metmuseum.org/art/collection/search/437680). The unchanged download includes a black surround and irregular canvas edges. `imageBounds` crops the image to pixels (57,36)–(1166,868) in the 1200 × 900 reproduction; this removes the surround and a narrow uneven peripheral strip without removing the signature or main subjects.
- Claude Monet, *The Houses of Parliament, Sunset*, 1903, National Gallery of Art, Chester Dale Collection, 1963.10.48. [Public-domain museum image](https://www.nga.gov/artworks/46523-houses-parliament-sunset).

This notice is bundled into the application's Resources directory. Code remains MIT; the Waterloo image and its visual derivatives retain their separate CC BY-SA 4.0 terms.

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
