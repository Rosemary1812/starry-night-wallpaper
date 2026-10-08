# Art direction and known failure patterns

Use these as examples to reason from, not universal presets. Inspect the actual selected reproduction and preserve the artist's structure, color and composition.

## A useful motion plan

Record the following alongside the evidence:

- Source/version, crop, intended desktop aspect ratios, loop duration and controls
- Active regions with plausible directions, displacement scale and relative phase
- Fully fixed regions and fine silhouettes to protect
- Whether lighting may change, where, and why
- What would make this animation fail visually

For a quiet harbor, a plan might animate short horizontal water strokes at depth-dependent amplitudes, make reflections move with nearby water, and keep boats, figures, sun, masts and buildings rigid. The distant water should not move at the same scale as the foreground. Inspect whether painted strokes support this interpretation.

## Examples from this collection

- **Water Lilies:** slow, mainly horizontal pond motion around lily clusters. Protect complete clusters; keep their edges crisp. Avoid warping flowers or making the pond pulse as a single sheet
- **Stacks of Wheat:** geometry can remain entirely still. A faint local warm-sky luminance change may be sufficient. A coarse changed-pixel threshold can miss intentional one-level RGB changes; measure opposite light phases and inspect lossless frames
- **Rhône:** direction and amplitude vary with water depth; reflections belong to the river. Keep shoreline, foreground people, boats and rigging still
- **Cypresses:** follow cloud curls and small exposed wheat tips where the paint supports it. Protect the cypress, mountain ridge and foliage rather than applying broad elastic distortion
- **Sunrise:** restrained water/reflection ripples. Preserve the sun, harbor, all boats and figures, signatures, and thin silhouettes

A new portrait or sharply geometric still life may have no suitable moving region in this pipeline. Recommend a still image or a specifically justified alternative instead of forcing water/cloud warps onto it.

## Mask and sampling decisions

Coordinates originate in the original image, then pass through `imageBounds` and aspect-fill. Check this transform in thumbnails, masks, preview, verification samples and exports. A mask that fits the uncropped image can still be wrong after a crop or y-axis flip.

Trace silhouettes, not only a few central points. Fine ropes, signatures and small people matter at full resolution. Add a margin compatible with the maximum displacement and mask feather. Inspect the **active side** as well: unprotected water sampling through a boat creates stretched or doubled edges while the boat's own pixels remain stationary. Path-aware displacement attenuation can help, but must be empirically tested at maximum supported strength.

Keep a separate, manually reviewed binary expected-protection mask for QA. White means must remain fixed. Do not generate it by thresholding the production mask and call that independent validation. Add separate ROI masks for active-side boundary bands and intended motion where helpful.

## Reject these shortcuts

- Whole-image rubber-sheet wobble; identical frequencies/directions across distinct materials
- Unmotivated global exposure breathing, especially when it changes rigid subjects
- Hard mask edges or oversized feathers that erase the motion or create halos
- Blending warped and original imagery twice, leaving soft double edges
- Declaring safety from a few anchor samples or a mask overlay alone
- Inflating amplitude solely to satisfy a generic motion threshold
- Treating 4-fps GIF playback as evidence of smooth 30-fps motion
- Comparing lossy encodes to prove exact protected-pixel equality

Inspect full composition and close-up boundary crops at normal playback speed. Pause at peaks, compare neutral and animated frames, and inspect the last-to-first transition. Numbers can locate defects; they cannot certify tasteful motion.
