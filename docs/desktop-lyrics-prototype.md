# Desktop lyrics prototype

Historical manual-import implementation. For the newer automatic-lookup and invisible-window changes, see [automatic lyrics](automatic-lyrics.md); the native acceptance evidence below does not verify those changes.

Current acceptance results and limitations: [2026-10-23 real-song acceptance](desktop-lyrics-acceptance.md). Dated evidence sections below are historical and are superseded where the newer report says so.

## Acceptance criteria (defined before implementation)

- Opt-in companion menu; disabled by default. No changes to WallpaperExtension or wallpaper installation.
- One transparent, borderless, click-through desktop window per attached display. Rebuild on screen changes; join Spaces without becoming key; hide during display sleep and recalibrate on wake.
- Read Music only while enabled through its public AppleScript dictionary. Never launch Music automatically. Distinguish not running, no track, denied automation, paused and read failure. Denial stops polling until explicit off/on retry.
- A user-selected UTF-8 LRC binds to the sampled current track for this app session. No network lookup or automatic matching. Track changes hide unmatched lyrics.
- Parse multiple timestamps, fractional seconds and signed millisecond offset; ignore metadata/malformed lines; deterministic ordering at duplicate times. Show previous/current/next line; no line highlighted before its timestamp.
- Extrapolate playing position with monotonic uptime, recalibrate each poll, freeze on pause, reset on unavailable state. Respect Reduce Motion.
- Exercise parser, timeline boundaries, seek, pause/resume, track change and unavailable states with deterministic tests. Build companion and run native overlay smoke verification where available. Report manual gaps separately.

## Architecture

`LyricsCore.swift` contains value types, LRC parsing and a playback timeline with an injected monotonic timestamp. `MusicPlaybackSource` reads public Apple Events described by the installed Music scripting dictionary, using a running process ID to avoid launching Music. It caches stable-ID track metadata and checks track identity again after position reads. Direct events replace the initial NSAppleScript implementation. No undocumented notifications or private Music endpoints are used.

`DesktopLyricsController` owns the serial sampling worker, timers, per-track documents/offsets and AppKit windows. While enabled it samples every 250 ms without overlapping requests and renders at 30 Hz using monotonic time. Common run-loop modes keep lyrics updating while menus are open. Position is anchored at sample completion; Apple Events latency is not added back speculatively. An asynchronous file panel keeps the main run loop available.

Appearance defaults to screen center, with a larger current line, subdued neighbors, a soft dark backing and short transitions. Center/bottom placement and larger type persist in UserDefaults. Per-track timing offsets change in 250 ms steps and remain session-local. An earlier offset selects lyrics using playback time plus the offset.

The import action explicitly binds to the current track and rechecks identity after the file panel closes. Stable library IDs are preferred; title/artist/album/duration form the fallback identity for tracks without an ID. This fallback cannot distinguish different recordings with identical metadata. No timestamped lyrics are inferred from Music's plain-text lyrics.

## Manual acceptance route

Enable Desktop Lyrics from the app menu or status menu, start Music, select Import LRC for Current Track, and choose a local file. Use an LRC aligned with that recording. Pause/resume, scrub both directions and switch tracks. Deny Automation once and retry by toggling off/on after changing System Settings. Test Music closed, stopped and a non-library autoplay track. Move through Spaces/Mission Control, attach/remove a display, enable Reduce Motion, then sleep/wake and lock/unlock. Quit must remove all overlays.

Phase one deliberately does not persist imports, timing offsets or the enabled setting. Appearance settings persist. Overlay visibility on lock screen is not a supported feature.

## Verification evidence (2026-10-22)

- PASS: `zsh scripts/verify-lyrics.sh`: 26 assertions for parsing, Unicode, offsets, repeated stamps, exact boundaries, duplicate ordering, duration clamp, pause/resume, seeks, switching and all unavailable states.
- PASS: complete companion `swiftc -typecheck -swift-version 5 -module-cache-path .module-cache` over the sources listed in build.sh. Existing AVFoundation deprecation warnings on the installed macOS 27 SDK remain.
- PASS: `CLANG_MODULE_CACHE_PATH="$PWD/.module-cache" SWIFT_MODULECACHE_PATH="$PWD/.module-cache" STARRY_ASSETS_DIR=/Users/lulingxi/Coding/starry-night-wallpaper/assets STARRY_SKIP_EXTENSION_BUILD=1 zsh build.sh`. Build required running outside the sandbox for iconutil; the initial sandbox attempt failed with Invalid Iconset. Assets were read from the primary checkout, never modified.
- PASS: production AppleScript compiled with `osacompile` against installed Music dictionary outside the sandbox. This confirms syntax, not authorization or playback behavior.
- PASS: `"Starry Night.app/Contents/MacOS/StarryNight" --lyrics-smoke "$PWD/dist/lyrics-evidence"` launched the actual companion executable and exited normally. One native AppKit window on the connected display: visible, click-through, not key, not opaque, level -2147483622, frame (285, 90, 900, 210). Evidence: `dist/lyrics-evidence/report.txt` and `overlay-0.png`. The image was inspected: three centered lines with brighter current line. This is a native view capture, not a desktop composite or WallpaperAgent result.
- PASS: `scripts/verify-source.py` using bundled Python with Pillow; `python3 scripts/verify-localization.py` (111 existing keys); `git diff --check`.
- PASS: primary checkout's binary diff and porcelain status match the before snapshots. No changes under WallpaperExtension, no staging, commits or pushes.
- NOT RUN: live Music synchronization and Apple Events permission allow/deny, non-library autoplay identity behavior, click delivery to underlying desktop, multi-display hotplug, Spaces/Mission Control, full-screen apps, Reduce Motion visual transition, sleep/wake and lock/unlock. These require interactive acceptance. Gallery interaction, video export and WallpaperAgent were not exercised by this test.

## Remaining limitations and next phase

The nominal polling interval is 250 ms; Apple Events latency and scheduling add to seek/track-change detection time. Reads can time out; stale lyrics clear when the error arrives. Track fields are sequential event reads rather than an atomic snapshot. Library identity is rechecked; fallback metadata identity cannot resolve all autoplay races. A Music process can exit between the running-app check and event dispatch. LRC accuracy and alignment remain the user's responsibility. This prototype uses English menu text and keeps documents in memory for the current session. Long lines truncate to two rows; duplicate timestamps select the final entry rather than grouping translations.

Do the unverified interactive acceptance checks before expanding scope. A third-party lyric provider would need explicit rights, matching, cache and error behavior. Wallpaper extension integration needs a separate feasibility decision because the current extension plays prerendered video. This overlay does not demonstrate that integration.

## Interactive follow-up (2026-10-22)

Operated the actual companion and Music using native UI automation. Music was already running and the adapter successfully reported several real current tracks as playback advanced. No new authorization prompt appeared; this does not test first-time permission grant or denial.

Added an explicitly labeled `Load Timing Demo (Not Song Lyrics)` menu action. It creates original Chinese test text in local LRC format at five-second intervals, binds it to the current track, and uses the same timeline and window renderer. It provides no song lyrics and contacts no lyric service.

PASS: loaded this demo for the playing track, closed the gallery, and inspected the native desktop window's three text rows. Paused Music at approximately 47 seconds; the overlay displayed rows at 00:40, 00:45 and 00:50 and stayed unchanged on a later observation. Resumed playback through Music's native button. This verifies actual public-script playback reads and the live window path, beyond the earlier fixture-only smoke check.

The UI tool's Finder and app screenshots returned white images. The overlay-only capture revealed faint white text against a white capture background; it did not include the wallpaper. Desktop composite contrast and motion quality remain unverified. No wallpaper was changed.

The file chooser initially kept Open disabled for the selected .lrc. Removed reliance on system LRC type registration and added explicit file-extension validation, with files enabled and directories disabled. Successful file-picker import still requires a follow-up check; the demo action must not be counted as that check. Build and the 26 core assertions pass after the changes.

## Real-song import validation (2026-10-23)

The user authorized downloading real timed lyrics for a local test. Downloaded LRCLIB record 9708865 for Fiona Sit, 奇洛李維斯回信, album F, duration 242 seconds. Music reported the same title/artist/album and a 4:02 duration while paused. The file and source metadata are in ignored `dist/lyrics-local/`; no lyrics were added to source control or app resources and the app has no network provider.

Reproduced the disabled Open button with a selected readable .lrc in the running native picker. Changed the presentation from nested `runModal()` to asynchronous `begin`, explicitly activated the app, and separated file loading from picker presentation. After rebuilding and restarting, selecting the actual downloaded LRC enabled Open; clicking it loaded the real text in the native overlay. This supersedes the prior unresolved import result. The exact contribution of activation versus modal-loop removal was not isolated.

Live checks: paused Music at about 47 seconds and observed the expected real lyric neighborhood (LRC timestamps 38.14, 44.68, 50.65). Resumed, observed changing real lyric rows, then paused at about 74 seconds and observed the corresponding later rows remaining fixed. Changing to another track hid the lyrics; returning to the original track reused its imported document. Restarted the original recording from the beginning, resumed playback, and closed the gallery to leave the real lyric window available on the desktop.

The native slider did not accept automation's attempted numeric seek; a subsequent right-arrow action changed tracks instead. Arbitrary scrubbing therefore remains NOT VERIFIED. No audio was captured or listened to by the agent: these checks establish position-to-LRC selection, not measured vocal alignment or millisecond timing accuracy. Desktop composite visual quality, Spaces and multi-display checks remain unverified.

PASS: companion build after this change, 26 core checks, and `git diff --check`. No commits or pushes.
