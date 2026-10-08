# Seven new wallpapers: integration validation

This PR adds Impression, Sunrise and six separately masked works: Waterloo Bridge (Sunlight Effect, 1903), Nocturne: Blue and Silver—Bognor (1871–1876), Approach to Venice (1844), Cliff Walk at Pourville (1882), The Bridge at Villeneuve-la-Garenne (1872), and The Houses of Parliament, Sunset (1903).

The existing five IDs and rendering behavior remain intact; this branch does not contain the separate four-wallpaper refinement. New IDs append at 5–11. Keyboard equivalents remain single characters: Command-1…9, Command-0, then Option-Command-1/2. Native gallery checks cover nineteen scenes, including new works in light/wide and dark/narrow windows.

## Checks performed

- Twelve metadata records, filenames, build/download/verification registrations and shortcut uniqueness checked
- New source bytes matched the individually examined museum/Commons reproductions
- Six new works passed actual cloud-browser Canvas CPU reference runs: 24-second endpoint equality and 58 protected subject anchors; Sunrise separately passed 9 anchors and exact loop equality
- Dedicated motion geometry preserves architecture, boats, people, cliff outlines and signatures; new six use constant illumination, not full-image brightness modulation
- The Sisley crop removes the downloaded black surround consistently across thumbnails, preview and export
- Source, shell, Python/JavaScript syntax and git diff checks pass

The browser previews use motion arithmetic translated from Sky.metal and protection polygons extracted from Swift. Only the seven additions are supported by this development preview command. Its Pillow 8px expansion/4px blur approximates CoreImage; JPEG decoding and numeric precision may differ.

**Not run:** native Swift/Metal or WebGL compilation, Mac keyboard events/layout, native performance, AVFoundation export, desktop/lock-screen playback. Linux has no macOS SDK; the cloud browser did not provide WebGL2. The existing untracked Starry Night image and seed video must be supplied for a full Mac build.

## Image rights

The Waterloo reproduction is CC BY-SA 4.0. Its attribution and same-license requirement for visual derivatives are separate from the MIT source license, documented in THIRD-PARTY-NOTICES.md and bundled into app Resources. Other added reproductions have the listed public-domain/open-access status.

Run `python3 scripts/verify-source.py` for static integration checks; `python3 scripts/preview-artworks.py --artwork waterloo-bridge` generates a local development preview. On a suitable Mac, prepare the existing two source assets, fetch the additional artwork images, then build and run the native verification scripts.
