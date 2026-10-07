# Third-party notices

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
