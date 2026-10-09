# Twelve-painting localization integration

This change adds 63 resource entries: the name, artist, and existing motion
description for seven paintings in Simplified Chinese, Traditional Chinese,
and English. It also updates the three wheat-stack motion descriptions to match
the warm-sky wording used with PR #1. The descriptions explain the app's motion;
they do not add art-history claims.

The added paintings are Impression, Sunrise; Waterloo Bridge; Nocturne: Blue
and Silver, Bognor; Approach to Venice; Cliff Walk at Pourville; The Bridge at
Villeneuve-la-Garenne; and The Houses of Parliament, Sunset.

## Dependency boundaries

The PR base is `codex/native-gallery-localization`, PR #4 at
`1baab7868ab458bf92cbd268f11ba382e9631349`. That branch supplies the native UI,
fonts, localization loader, and the main catalog of five paintings.

PR #2 at `da84bd6bd6be221421df177bcbcf6dfe93b1d178` supplies the seven new
catalog entries and renderers. PR #1 at
`866c71bf8647414bf54324cd41bb7b97d64198ac` supplies the earlier motion refinements.
Main was `8f4c5bae15076f6a33466b648adde8eac1401c44` when the dependencies were
checked. Those commits are validation inputs, not additional commits in this PR.
This diff does not change the catalog, crops, masks, shaders, build asset list,
fonts, or production gallery layout. The latest PR #2 shader revision is used only
in the separate integration fixture; it is not copied into this PR.

The base still displays five paintings. Extra translation keys are dormant until
the catalog is integrated. Preserve PR #2's artwork IDs, crops, asset list, and
single-character shortcuts; retain PR #4's localized computed metadata and
single-preview UI. The layout checks discover `Artwork.allCases` rather than
referring to the seven new Swift enum cases, so this PR builds on its stated base.

After PR #4 lands, update this branch with the merged main history and confirm
the comparison contains only this resource/test change before retargeting main.
With a squash merge, simply changing the base may expose the parent commits;
resolve that with a normal merge of main or a fresh clean follow-up branch, not
a force push. Complete twelve-painting acceptance also requires integrating
PR #2 and reconciling the PR #1 motion-description dependency.

## Repeatable checks

`python3 scripts/verify-localization.py` checks duplicate, missing and empty
resource keys, matching format placeholders, the brand, and all twelve paintings'
names, artists, and descriptions in each language. It needs Python 3 and macOS
`plutil`, without third-party Python packages. The gallery verification script
runs this check before building.

The native checks cover every registered painting in every language, plus the
existing wide/narrow, light/dark, and breakpoint scenes. They verify title-font
glyphs and resolved system-font glyph runs for artists and descriptions. The
expected-catalog guard makes missing integration dependencies an explicit failure:

```sh
STARRY_ASSETS_DIR=/path/to/licensed/assets zsh build.sh
STARRY_VERIFY_EXPECTED_ARTWORK_COUNT=5 \
  'Starry Night.app/Contents/MacOS/StarryNight' --ui-check dist/base-evidence

# In the separately prepared twelve-painting integration checkout:
STARRY_VERIFY_EXPECTED_ARTWORK_COUNT=12 \
  'Starry Night.app/Contents/MacOS/StarryNight' --ui-check dist/integration-evidence
```

Local integration validation uses a detached, task-owned checkout of PR #4 plus
the existing twelve-painting composite `c69a9dc8b93a9c34f533ea4c87b2527f732fcf0a`
of the original PR #2 at `baa5012` and pinned PR #1, plus the published shader
update from `baa5012` to `da84bd6`. Only its catalog, masks/render checks, shader and
asset packaging are combined with the same published UI and these resource/test
files. The fixture's input commits and file hashes are recorded in its ignored
`dist/integration-inputs.json`. No dependency branch is changed or pushed.

These checks are offscreen AppKit runs. Synthetic events drive the continuous
sequence, and static fallback snapshots are not a physical-mouse recording or
Metal presentation capture. Physical mouse/trackpad behavior, Tab traversal,
the visible Metal first-frame handoff, and quit/relaunch language persistence
remain unverified after the earlier locked-Mac check. Wallpaper installation,
application and lock-screen playback are outside these checks. Shader motion
quality and loop regression are not revalidated by a localization-only change.
