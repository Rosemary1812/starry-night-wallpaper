# Interface fonts

`SourceSerif4Variable-Roman.otf` is Adobe's unmodified Source Serif 4 variable
OpenType font, version 4.005. Copyright © 2014–2023 Adobe; Reserved Font Name
“Source”. It is distributed under the SIL Open Font License 1.1. The complete
copyright and license are in `SourceSerif4-LICENSE.md` and accompany the app.

- Official font: https://raw.githubusercontent.com/adobe-fonts/source-serif/release/VAR/SourceSerif4Variable-Roman.otf
- Official license: https://raw.githubusercontent.com/adobe-fonts/source-serif/release/LICENSE.md
- Retrieved: 2026-10-08
- Font bytes: 1,884,148
- Font SHA-256: `867b73c6a954a4a64616906d179f94572a748790a1d022ebeeff07f56ea0221a`
- License bytes: 4,491
- License SHA-256: `c21d7293d87b6d7ab1d0229a2f55b77f33a7613a6a4e66f6693d68d7d8d09464`

The app registers the font only for its own process. The brand uses the native
variable weight axis at 500 (Medium), size 20. English titles use weight 400,
size 24. No font was subsetted, renamed, or installed into macOS. No standalone
static Medium font was available in the official release.

Simplified Chinese titles use the installed `STSongti-SC-Regular`, and
Traditional Chinese titles use `STSongti-TC-Regular`, both at 23 points. These
Apple-supplied font files are neither copied nor redistributed. Metadata and
controls use the system font. If the selected font is unavailable, the app falls
back to the system serif design, then the system font.

The official Adobe Source Han Serif regional Regular fonts were evaluated:
SC 24,543,332 bytes and TC 24,542,148 bytes, totaling 49,085,480 bytes. They were
not bundled. Using installed regional Songti avoids that 49 MB increase.
