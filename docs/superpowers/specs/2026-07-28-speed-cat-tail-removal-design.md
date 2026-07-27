# Speed Cat Tail Removal

## Context

The approved Speed Cat mark currently combines a centered white cat head,
yellow lightning bolt, indigo tile, and one small detached pale-indigo wave.
The final visual direction removes the wave entirely. This is a subtractive
refinement only: the centered cat, lightning, scale, colors, tile, and platform
coverage remain unchanged.

## Approved visual direction

- Keep the white cat-head silhouette horizontally centered on the 1024 px
  transparent master.
- Keep the existing yellow lightning shape and its position relative to the
  cat.
- Remove every pale-indigo trail or wave pixel from the canonical mark.
- Do not replace the wave with another tail, line, dot, accent, or motion mark.
- Preserve the existing foreground scale and indigo gradient tile.

The finished mark contains exactly two foreground color classes: the white cat
and yellow lightning. The empty area to the left of the cat becomes intentional
negative space.

## Implementation approaches considered

### 1. Remove the trail in the deterministic source pipeline — selected

Continue loading the immutable source, discard every pixel classified as the
trail color, translate the cat and lightning to the already-approved centered
position, and stop before drawing any replacement wave. Regenerate all raster
outputs from this canonical mark.

This is reproducible, preserves the approved cat shape, and updates every
platform from one source of truth.

### 2. Erase the tail from generated PNG files

Editing each output would be visually quick but would create inconsistent
assets, leave future regeneration broken, and risk antialiasing residue.

### 3. Redraw the complete logo

A full redraw could remove the tail but would unnecessarily change the approved
cat and lightning. It is outside this focused refinement.

## Platform behavior

`scripts/branding/build_icon_set.py` remains the source of all raster assets.
`build_refined_mark` produces a transparent centered cat-and-lightning mark with
no trail pixels. macOS, iOS, Android legacy launchers, Windows, Flutter assets,
and the color tray icon are regenerated from it.

The Android adaptive launcher and monochrome notification vectors remove their
separate stroked wave paths. The macOS template tray asset remains the white cat
silhouette, so its appearance is unchanged.

## Verification

- The canonical transparent mark contains no pixels classified as
  `#C6CDFF`.
- The cat-head horizontal center remains within 1 px of x=512.
- The generated brand logo contains no trail-color pixels.
- The asset validator rejects any mark containing a trail-color component.
- Android launcher and notification vectors contain no detached stroked path.
- Existing asset dimensions, Windows ICO sizes, Flutter brand placement tests,
  static analysis, and the full unit suite remain green.
- The macOS Debug application is rebuilt and relaunched before visual
  inspection.

## Out of scope

- changing the cat silhouette, lightning, foreground scale, tile gradient, or
  corner radius;
- adding text, facial features, outlines, animation, or other decorative marks;
- merging the feature branch into `main` without explicit user approval.
