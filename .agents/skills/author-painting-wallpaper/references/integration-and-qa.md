# Integration and verification

## Preserve these contracts

The app appends `Artwork` enum cases because raw values are persisted and also select Metal branches. Keep existing IDs/order, filenames and shortcuts stable. `NSButton.keyEquivalent` must be one character; the original five-artwork source uses Command-1…5. The checker also supports the expanded twelve-artwork source's Command-1…9, Command-0, then Option-Command-1/2 mapping. More entries require a deliberate noncolliding mapping, not a multi-digit string.

Update the appropriate surfaces together:

- `Artwork.swift`: appended case, all metadata, image bounds, shortcut mapping
- `Sky.metal`: selected branch, motion, neutral-strength behavior, loop period
- `StarryNight.swift`: subject mask, coordinate transforms, verification samples; keep Swift/Metal parameter ABI aligned
- `build.sh`, `scripts/fetch-artworks.sh`, `scripts/verify-artworks.sh`: assets and iteration
- `GalleryView.swift`, `GalleryVerification.swift`: selection, labels, shortcuts and representative layouts
- `THIRD-PARTY-NOTICES.md`, both READMEs: exact reproduction rights, changes, credits and accurate verification claims

Do not silently drop the separately supplied Starry Night image/video dependency. Source-only work can proceed while reporting absent assets, but a distributable/native application still needs them.

## Provenance record

For each image record its title/artist/year, museum identifier when available, exact image URL, catalog/file-page URL, access date, source SHA-256, pixel dimensions, source license and license URL, required attribution, crop coordinates, and derivative modifications/obligations. Save this next to the task evidence and update distributed notices. A JSON record accepted by preflight has this minimal shape:

```json
{
  "slug": "impression-sunrise",
  "source_url": "https://upload.wikimedia.org/wikipedia/commons/5/59/Monet_-_Impression%2C_Sunrise.jpg",
  "record_url": "https://commons.wikimedia.org/wiki/File:Monet_-_Impression,_Sunrise.jpg",
  "license": "Public domain reproduction; verify the file record",
  "license_url": "https://creativecommons.org/publicdomain/mark/1.0/",
  "attribution": "Claude Monet, Impression, Sunrise, 1872, Musée Marmottan Monet",
  "sha256": "replace with the exact downloaded image SHA-256",
  "dimensions": [5773, 4478],
  "derivative_obligations": "Record the verified obligations for this reproduction",
  "changes": "Describe resize, crop and animation changes"
}
```

This is an example record structure, not verified licensing evidence. The checker only checks completeness/hash/dimensions; read the actual source page to substantiate rights. A public-domain painting does not imply every reproduction has identical terms. In particular the collection's Waterloo reproduction carries separate CC BY-SA 4.0 attribution/share-alike terms.

## Read-only commands

Run from the repository root; Python 3 is needed. Preflight uses Pillow only for image inspection. Frame checks require Pillow and NumPy. Report missing dependencies; install only within existing authorization.

```sh
S=.agents/skills/author-painting-wallpaper
python3 "$S/scripts/preflight.py" --repo . --artwork impression-sunrise --assets-dir /path/to/assets --provenance /path/to/source.json
python3 "$S/scripts/check-integration.py" --repo . --baseline /path/to/clean-baseline-repo
```

`--baseline` checks that old IDs and slugs remain an unchanged prefix. Omitting it prints that historical ID compatibility was not checked. The integration checker reads the actual catalog and recognizes the original five-entry source as well as twelve entries. The original five-entry build does not bundle third-party notices, so it correctly fails that distribution gate; the check does not silently waive it for an older branch. It does not assume the cloud preview helpers exist on older branches. Regex-based source checks fail explicitly when source layout is unsupported; revise the checker if the app adopts a different representation.

On a branch that includes the expanded source verification and preview helpers, also run:

```sh
python3 scripts/verify-source.py
python3 scripts/preview-artworks.py --artwork impression-sunrise --output dist/artwork-previews/impression-sunrise
```

That expanded source checker expects twelve entries; update its expected catalog intentionally for additions. The preview helper derives motion from native source and approximates Core Image masks. Its CPU/WebGL results are not native Metal results. If these helpers are absent, do not invent their output or install them as part of unrelated work.

## Native Mac route

On an authorized Mac with assets and Xcode Command Line Tools:

```sh
zsh scripts/verify-gallery.sh
"Starry Night.app/Contents/MacOS/StarryNight" --verify --artwork impression-sunrise
"Starry Night.app/Contents/MacOS/StarryNight" --export dist/impression-sunrise.mp4 1920 1200 --artwork impression-sunrise
```

The gallery script rebuilds, captures light/dark and window-size cases, and invokes artwork checks; it is not read-only. Review keyboard selection, live controls, busy-state recovery, crop consistency and the exported video. The current `--verify` checks loop endpoints, sparse fixed samples and a few motion phases. Those are useful regressions, not a full-cycle silhouette proof.

For lossless evidence use a renderer harness calling `Engine.pixels` with an explicitly recorded strength, time, width and height, and save PNGs. The CLI `--snapshot` has fixed defaults; do not assume it can export neutral-strength images or change resolution through undocumented arguments. A cloud harness may use the generated source reference but must label itself accordingly.

Wallpaper extension installation, application and lock-screen playback need their own authorized native checks. Export success does not prove those paths. Report separately: static; CPU reference; WebGL; native Metal; native gallery; encoded export; desktop/lock screen. Use PASS / FAIL / NOT RUN with the actual command or reason.

## Helper regression tests

Run `python3 .agents/skills/author-painting-wallpaper/scripts/test_helpers.py` after changing the helpers. These generate temporary synthetic 720-frame sequences and check positive/negative behavior. The integration regression uses temporary copies of the source to test missing notice bundling, a valid static integration, and changed historical IDs without requiring the checkout to pass the distribution gate. They test the tools, not the artistic quality or native execution of any painting.
