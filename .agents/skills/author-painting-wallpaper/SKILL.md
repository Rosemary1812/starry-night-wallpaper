---
name: author-painting-wallpaper
description: Add or refine a painting's animated wallpaper in this AppKit/Metal repository, including image provenance, painting-specific motion, protected subjects, gallery integration, and rendering evidence. Use for painting additions or motion/mask quality work, not unrelated app changes.
---

# Author a painting wallpaper

Deliver a restrained animation that respects the painting and works in the native app. Judge whether the image suits this renderer first; some paintings should remain still or need a different technique. The skill is a workflow, not a guarantee that arbitrary images can be animated well.

## Start with the actual source

1. Inspect the full-resolution painting, its current crop, and any existing animation. Read the user's requested subjects, motion, and constraints. Do not decide masks from a thumbnail or a description alone.
2. Run the read-only preflight from the repository root:
   ```sh
   python3 .agents/skills/author-painting-wallpaper/scripts/preflight.py --repo . --artwork impression-sunrise
   ```
   It reports capabilities and missing inputs; it does not download, install, publish, or change wallpaper. Use `--assets-dir` or `STARRY_ASSETS_DIR` if needed. Substitute the actual slug. For a new, unregistered painting add `--image /path/to/source.jpg`.
3. Verify the **specific reproduction's** source and license, not only the artist's death date. Record exact download/record URLs, source SHA-256, dimensions, crop, attribution, and derivative obligations. Stop redistribution if rights are unresolved. Read [integration-and-qa.md](references/integration-and-qa.md) for the record and integration contract.

## Design before tuning

Write a short per-painting motion plan: active regions, direction/scale/rhythm, fixed subjects, lighting policy, and reasons rooted in the image. Read [art-direction.md](references/art-direction.md) for examples and failure patterns. Preserve the composition; a shared generic wave is not an adequate plan.

Trace complete silhouettes, including small boats, figures, rigging, architecture, signatures, and their margins. Review the mask overlay at native detail and at desktop crops. Keep validation masks independently annotated from the shader mask so a wrong silhouette cannot validate itself. Check motion near boundaries, not just protected anchor points.

Implement within the existing pipeline in `Artwork.swift`, `StarryNight.swift`, and `Sky.metal`. Keep stable artwork IDs, coordinate/crop transforms, and the Swift/Metal parameter layout. Iterate one painting at a time. Do not rewrite the whole renderer or expand the task to new paintings without a reason in the request.

## Verify at the right level

Read [integration-and-qa.md](references/integration-and-qa.md) for exact commands and [frame-evidence.md](references/frame-evidence.md) before capturing frames.

- Static integration checks prove registrations and invariants, not compilation or visual quality
- Shader-derived CPU/WebGL previews are development references; mask feathering, sampling, and color can differ from native Metal
- Native Metal frames and AppKit checks require a Mac; export and wallpaper/lock-screen playback are additional, separate checks
- Use a full 24-second cycle at 30 fps (720 playback frames plus the 24-second endpoint) for the existing default cycle, or explicitly record a changed cycle. Use lossless frames for pixel tests, and compare before/after for refinements
- Require dense protected-region/boundary checks, visible but restrained intended motion, a clean loop transition, and normal-speed visual review. Check the native exported movie separately; codec noise can mimic movement or bury subtle light changes. A low-fps GIF is not timing evidence

Run the bundled integration and frame checks, then the repository's available native checks. A failed or unavailable stage stays failed or untested; do not collapse partial success into a blanket pass. If a check exposes a problem, fix and rerun the affected stages. Stop dependent completion claims when a required platform or authorization is missing.

## Deliver

Return the implemented changes, source/license record, motion rationale, mask overlay, normal-speed preview, before/after metrics when applicable, commands/results, and explicit untested stages. Include file paths or review links that actually exist. Publishing, installing, applying wallpaper, or changing system settings remains subject to the user's authorization.
