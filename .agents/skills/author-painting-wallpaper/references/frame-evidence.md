# Frame evidence contract

## Prepare matching inputs

Capture `frame-0000.png` through `frame-0719.png` at t = index/30 seconds and `frame-0720.png` at exactly 24 seconds. The last file is an additional endpoint, not a playback frame. For a different cycle/fps pass both explicitly; duration × fps must be integral. Keep resolution, crop, color processing and strength fixed. Save a neutral/strength-zero frame rendered by the same backend, not an independently resized JPEG.

Prepare same-sized binary PNG masks, independently reviewed against the source: white (255) is selected and black (0) is unselected. The required protected mask covers expected fixed silhouettes. An optional motion mask covers an intended active region and must not overlap protected pixels. Do not use a feathered production mask as expected truth.

Keep renderer identity, source/image hashes, settings, crop, and code revision in an evidence note. `cpu-reference`, `native-metal`, and `encoded-video` must remain distinct. Do not re-label shader-derived CPU output as a native render.

## Run the checker

```sh
S=.agents/skills/author-painting-wallpaper
python3 "$S/scripts/check-frames.py" \
  --frames dist/evidence/sunrise/after \
  --neutral dist/evidence/sunrise/neutral.png \
  --protected-mask dist/evidence/sunrise/expected-fixed.png \
  --motion-mask dist/evidence/sunrise/expected-water.png \
  --kind cpu-reference --fps 30 --duration 24 \
  --min-motion-mean 0.02 \
  --before dist/evidence/sunrise/before \
  --report dist/evidence/sunrise/metrics.json
```

Use `--before` for a refinement when comparable pre-change evidence exists; omit for a new painting. Record why a baseline is unavailable rather than fabricate it. Motion is measured as each pixel's maximum RGB temporal range over the full cycle; the reported mean uses that range in the motion ROI. The example threshold is illustrative, not a universal quality bar. Choose and explain thresholds before declaring acceptance; geometry-free luminance may legitimately be very small.

The checker requires all frames, validates binary masks, tests protected pixels against neutral throughout the cycle, and reports the inner silhouette boundary separately. It checks the endpoint and last-to-first jump against adjacent-frame changes across the whole frame, plus the motion ROI when supplied. A narrow motion ROI must not conceal a seam elsewhere. It streams frames rather than retaining the whole movie. It also reports before/after deltas; those numbers are evidence, not an automatic ranking of artistic quality.

For native/CPU lossless frames, defaults require exact protected pixels and equal endpoints. Select explicit tolerances only with a documented backend/rounding reason. Temporal seam ratio is a diagnostic with a configurable limit (default 2); endpoint equality alone is insufficient. The seam metrics average spatial changes and can hide a small localized jump amid stronger movement. Visually inspect close-up regions, velocity and direction through the wrap; a magnitude check does not establish derivative continuity. Rendering at maximum supported strength and multiple crops may expose defects that a default-strength test misses.

## Boundary and visual review still required

Dense protected-region checks do not detect all active-side dragging. Review close-up masks and moving pixels on both sides of silhouettes, especially rigging, parasols, lilies and signatures. Inspect peak-displacement frames against neutral, then play the **full 30-fps cycle** at normal speed. A stationary subject with a smeared halo is a failure even when every protected pixel passes.

For exported video, decode frames to PNG losslessly from the encoded stream, retain `--kind encoded-video`, and explicitly provide `--max-protected-delta` and `--max-loop-delta`. A 720-frame video normally lacks the 24-second endpoint: use `--no-endpoint`, which reports endpoint equality as NOT RUN but still checks wraparound. Never copy frame zero to fabricate an endpoint. Codec tolerances must come from measured export behavior and visible quality. These checks measure the decoded export; they do not prove the shader's protection or loop equality.

If the actual export includes the true endpoint, omit `--no-endpoint`. Keep pre-encode lossless evidence separately. Lossy noise and chroma changes can exceed the intended movement, especially in Wheat's subtle sky glow. Do not use encoded differences to claim pixels in the shader moved. GIFs are distribution previews only.
