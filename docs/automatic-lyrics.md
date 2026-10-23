# Automatic desktop lyrics

This extends `codex/desktop-lyrics` at `ed9cbd76c4fd380f0be010253b96b694e55539ab`.
The feature still runs in the macOS companion application, not in the video wallpaper extension.

## Use it

1. Build the companion with the existing `zsh build.sh` workflow. Its existing artwork assets and macOS SDK are still required.
2. Open Music and select a recording. Enable **Desktop Lyrics → Enable Desktop Lyrics** in the application or menu-bar menu.
3. Enable **Automatically Find Lyrics (LRCLIB)…** and accept the in-app explanation. This setting is off by default. Merely starting the app or enabling desktop lyrics does not opt you into networking.
4. The app looks for an exact recording match. Imported/cached lyrics appear without a network request. If the metadata is incomplete, the service has no exact timed result, or the connection fails, the menu explains that state and **Import LRC for Current Track…** remains available.
5. **Lyrics Earlier/Later by 0.25 s** saves a per-recording offset, bounded to ±10 seconds. Imported LRC takes priority over automatic results. Appearance and the automatic-lookup preference persist; the desktop-lyrics enable switch remains off at a fresh launch.

Turning automatic lookup off cancels queued/in-flight lookups and prevents new ones. Previously saved lyrics still work offline. Turning Desktop Lyrics off, losing the current Music track, display sleep, and track changes also cancel work. Re-enable online lookup when you want new downloads again.

## What is sent, and where

Only the current recording's title, artist, album and duration are sent in an HTTPS GET to `https://lrclib.net/api/get`. Music persistent IDs, audio, local files, account details, credentials and stored listening history are not uploaded. As with any network service, LRCLIB receives the request and ordinary connection information such as the client IP address. The client does not upload or publish lyrics.

The app identifies itself with a `StarryNight/0.3.0` User-Agent and project URL. The transport uses a fresh ephemeral session, no cookie or credential storage, no disk HTTP cache, normal TLS validation and no redirects. It limits streamed response bytes to 1 MiB, with a 12-second request and 15-second resource timeout.

Official API/source references checked during implementation:
- https://lrclib.net/docs
- https://github.com/tranxuanthang/lrclib/blob/main/server/src/routes/get_lyrics_by_metadata.rs
- https://github.com/tranxuanthang/lrclib/blob/main/server/src/router.rs
- https://github.com/tranxuanthang/lrclib/blob/main/server/src/errors.rs

No API key, new account, paid provider, private Music lyrics API, audio recognition, or third-party SDK is used. Availability of an API is not a blanket license to redistribute its lyrics. Downloaded lyrics stay in the user's local cache; no third-party song lyrics are bundled in this source change or its tests.

## Matching and fallback

The client requires nonempty title, artist and album and a finite duration between 1 and 3600 seconds, matching the endpoint's supported duration range. It independently validates the response even if the server reports a match:

- Title, artist and album must match after canonical Unicode, case and whitespace normalization only.
- Punctuation, diacritics, featuring credits and live/remaster/version labels are preserved. There is no broad title-only or fuzzy-search fallback.
- Duration must differ by no more than 2 seconds.
- A positive provider ID and nonempty synchronized LRC are required. LRC timestamps must remain within the recording duration plus 2 seconds.
- Instrumental, no timed lyrics, not found and rejected-version states are distinct. Plain lyrics are not presented as synchronized lyrics.

This deliberately favors a missing result over the wrong recording. Identical metadata does not prove two audio recordings are identical; matching cannot guarantee vocal alignment. A fixed user offset corrects a constant delay, not a different performance's tempo drift. Manual import is the fallback for stricter matches the provider cannot supply.

## Persistence and concurrency

`LyricsStore.swift` stores one bounded UTF-8 JSON record per exact recording in `~/Library/Application Support/StarryNight/Lyrics-v1/`. The recording key includes Music ID, title, artist, album and the duration, rather than a song title alone. SHA-256 creates a safe stable filename, and the full exact key is validated after reading. A record includes original LRC, origin, LRCLIB ID when applicable, offset and any negative retry deadline. Lyrics, provenance and offsets are atomically replaced together.

The store limits LRC to 2,000,000 bytes, encoded records to 4 MiB, total records to 4096, and aggregate storage to 64 MiB. It does not evict manual imports. A capacity, corruption or I/O failure keeps any loaded session lyrics usable and shows a storage warning rather than falsely claiming a save. Corrupt/newer-format files are treated as cache misses and are not silently overwritten.

`LyricsService.swift` confines file access and state to a serial utility queue. A 0.5-second debounce avoids looking up tracks immediately skipped; requests are separated by at least 2 seconds across tracks. Not-found/no-timed/mismatched results are cached for one hour; instrumentals for one day. Transient failures back off at least 60 seconds. HTTP Retry-After is honored across tracks without shortening longer deadlines. Negative-result deadlines are persisted per recording; provider-global cooldowns are also persisted so restarting on a different song does not bypass Retry-After.

Selection, toggle, sleep and manual import invalidate generation tokens as well as cancelling transport. A late response is neither rendered nor saved for a stale selection. Manual imports win both in memory and on disk. The process-local service working set is bounded to 64 recordings; persistent records provide offline reload. The original timing demo remains session-only.

Music playback still uses the public Apple Events adapter, 250 ms polling and a 30 Hz monotonic display timeline. Automation permission is still required; denial does not trigger any private API fallback. Lyrics are line-timed, not word-timed karaoke.

## Invisible-window styling

The previous view explicitly painted a black gradient panel. That paint path has been removed. The window remains clear, nonopaque, borderless, without a window shadow, click-through and unable to take key/main focus. Its view and labels have transparent backgrounds, no borders or material. Only the text glyphs have a small shadow.

The current line uses system typography at 30 pt (38 pt in large mode); neighbors use 18/23 pt and 52% opacity. Text is centered, wraps to at most two rows and uses a short opacity transition rather than a sliding panel. Reduce Motion disables that transition.

Open `docs/lyrics-style-preview.html` for an offline visual before/after simulation with invented text. It is not an AppKit screenshot or proof of native desktop compositing, Spaces, hit testing, or wallpaper behavior.

## Verification and reproducible commands

Portable checks require Swift with Foundation and FoundationNetworking:

```sh
bash scripts/verify-lyrics-portable.sh
# Or select a compiler explicitly:
SWIFTC=/path/to/swiftc bash scripts/verify-lyrics-portable.sh
python3 scripts/verify-source.py
python3 scripts/verify-localization.py
git diff --check
```

The portable harness builds separate core, store, provider and service test executables in Swift 5 language mode, with a temporary writable module cache. Network tests use injected transport/URLProtocol fixtures and original invented lyrics. They make no requests to the live lyric service.

The initial cloud implementation passed 375 checks on Linux with Swift 6.4.1. On 2026-10-23, the same suites passed on macOS 27.0.1 with Swift 6.4: core 110, store 133, provider 99 and service 33. Native validation found and fixed a macOS directory-alias issue that counted a replaced cache entry twice at the capacity limit. The companion and wallpaper extension built successfully with Xcode 27.1, and the isolated application's ad-hoc signature passed deep/strict verification. Existing AVFoundation deprecation and wallpaper-extension warnings remain.

The isolated `--lyrics-smoke` run used invented lyrics, disabled lookup and no persistent lyric store. AppKit checks verified displayed text, clear borderless windows, no window shadow, non-key/click-through properties and a fully transparent 20-pixel perimeter. Light/dark and large-text images were captured with native `NSWindow`/`NSView` rendering; they are not desktop WindowServer compositor captures. A local validation bundle can set `LyricsValidationStoreDirectory` to isolate its cache; the distributed Info.plist does not set this key.

The Mac was locked during validation. Actual desktop composition and click-through interaction, multi-display/Spaces, sleep/wake, Music Automation, the native file chooser and real-song networking remain untested for this change. No playback, volume, music library or system permissions were changed. Historical acceptance reports describe the earlier manual-import branch, not live validation of this automatic-lookup change.

Before release, build and sign on macOS with `zsh build.sh`; test first-time permission, both privacy choices, automatic lookup of multiple recording versions, offline restart, import priority, offsets, rapid skips, desktop contrasts, multiple displays, Spaces and sleep/wake. Do not run the live acceptance helper without intending its documented playback/volume changes.
