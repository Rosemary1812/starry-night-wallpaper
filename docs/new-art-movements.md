# New art movement studies

Branch: `codex/new-art-movements`. Source baseline: `73084fa`.

## Revision after visual feedback

The Great Wave has been removed from the catalog, shader, masks, resource download/build lists and translations. Its old ID 13 is not reused; Circular Forms and Concentric Circles retain IDs 14 and 15 and their shortcuts. Gallery positions now use a separate contiguous catalog index. The collection contains 15 works. The old downloaded source and evidence remain locally recoverable, but are not bundled.

The Scream's original horizontal oscillation did not track its painted contours. The revision uses four hand-traced sky ribbons with smooth interpolated tangents in original source coordinates. Their heights follow the upper shallow strokes, middle red/blue bands and lower golden arch above the ridge. A two-trace advection loop transports pigment continuously along these curves, at slightly different speeds per band, rather than reversing the whole region every half-cycle. The inscription, fjord, figures, bridge and signature remain outside the active region. No lighting changes are added.

Before frames remain at `dist/motion-studies/the-scream`; after frames and the new MP4 are at `dist/scream-refinement/`. Sources and reproduction rights are unchanged. The older skill preflight does not parse explicit enum IDs; repository checks validate the reserved ID and localized metadata instead.

The results below describe the initial four-work experiment, before this revision.

Revision verification: native build, 15-work visible GPU preview traversal, retained-ID/shortcut checks and 120 localization keys passed. Final 721-frame comparison at 640×845, strength 1.4: all 385,280 independently annotated fixed pixels remain identical to neutral; endpoints are identical; seam ratio 0.992 (ROI 1.005). Motion ROI temporal range changed from 30.22 to 26.71. The first expanded-mask attempt failed with 137 changed fixed pixels; pulling the upper feather back resolved it without relaxing tolerance. Full metrics: `dist/scream-refinement/metrics.json`.

Both 1280×800 desktop and 960×1268 full-composition 30-fps MP4 previews were exported. The desktop aspect-fill crop excludes most sky, so use `the-scream-portrait.mp4` to assess the ribbon changes. Native stills/overlay and playback launch were checked; this is not a claim of exhaustive normal-speed artistic approval, maximum-strength validation or decoded-codec pixel equality.

Four appended IDs preserve the original twelve paintings and their shortcuts. Option-Command-3 through 6 select the studies. `MotionStudies.swift` produces conservative masks; RGB identifies independent motion groups for the abstract works. The existing uniform layout and legacy shaders are unchanged.

## Motion plans

- The Scream, 1893: crop away the frame and right mounting strip; animate only the middle sky ribbons horizontally with a slight curve. Preserve the inscription, fjord, boats, figures, bridge and signature. The portrait composition is cropped vertically on a wide desktop, so the gallery's full-painting preview is the better view of the composition.
- The Great Wave, ca. 1830–1832: circulate interior blue strokes around the wave's curl. Preserve the outer crest, spray silhouette, inscriptions, all boats and Fuji. This first study intentionally keeps the exterior foam still; animating the complete crashing silhouette would require a different treatment of the exposed background.
- Circular Forms, 1930: three independently phased RGB regions follow the left oval, right large wheel and upper-right small disc. The small disc has its own rotation. Outer edges remain still; no illumination modulation.
- Color Study, 1913: stagger the twelve local circle phases. Keep quiet margins around the grid and paper edges. No global exposure pulse.

All new fields use integer-frequency sine phases over 24 seconds. Defaults are strength 1.4 and 30 fps. Zero strength returns the original sampling. Full source records, hashes, crop and credits are in `new-art-movements-sources.json`; distributed notices link the specific reproductions.

## Evidence

Native screenshots and mask overlays: `dist/evidence/`. Full-cycle PNGs and 1280×800 H.264 previews: `dist/motion-studies/`. Each lossless sequence contains 720 playback frames plus the actual 24-second endpoint. Neutral frames use the same Metal backend at strength zero. No prior animation exists for these new paintings.

`scripts/check-motion-studies.py` defines independent source-space fixed regions and motion regions, then runs the bundled checker. These cover the complete Scream foreground, Great Wave boats/Fuji/inscriptions, and abstract paper margins. They do not claim a pixel-perfect annotation of every foam edge or internal abstract grid line. Default threshold is mean temporal range 0.02 in the intended motion region; protected pixels and endpoints require exact equality.

Reproduce with the built app's `--capture-cycle dist/motion-studies/SLUG --artwork SLUG`, then run `scripts/check-motion-studies.py` with Pillow and NumPy installed. `--export PATH 1280 800 --artwork SLUG` produces the separate encoded preview.

The older skill preflight rejects the repository's existing localized title representation. The current repository source and localization checks are used instead. The CPU preview tool explicitly rejects the RGB studies because it cannot reproduce their native masks.

System wallpaper installation and lock-screen playback are outside this local preview test. Full-cycle checks use 640-pixel-wide native images at default strength; maximum-strength and all desktop-crop combinations remain untested.

## Results, 2026-10-22

- PASS: native AppKit/Metal build; 16-artwork loop endpoints and protected anchor samples; 123 matching localization keys; static catalog/resource/shortcut checks; `git diff --check`.
- PASS: 56 native gallery layout scenes, 210 continuous interaction simulation frames, slider wiring, busy recovery and production run-loop settling.
- PASS WITH LIMITS: all four full-cycle frame checks. Protected changed pixels and endpoint differences are zero for every study. Whole-frame seam ratios versus normal adjacent frames are 0.940, 0.995, 0.881 and 0.986 respectively, below the 2.0 diagnostic limit.
- PASS: four 24-second, 30-fps H.264 exports at 1280×800 produced by the native renderer.
- PASS: visible live previews for all 16 paintings, each completing 20–28 GPU frames during the live check; wraparound selections also passed.
- Reviewed source images, native stills and mask overlays. Full normal-speed artistic review and decoded-video compression metrics remain pending; the MP4 files are supplied for review. Do not treat these quantitative passes as final artistic approval.

The debug application was launched from this checkout and its accessibility tree confirmed 16 paintings and selection of Circular Forms. No wallpaper was applied and no release was published.
