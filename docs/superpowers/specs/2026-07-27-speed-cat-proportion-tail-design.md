# Speed Cat Proportion and Wave-Tail Refinement

## Context

The first Speed Cat rollout established the approved white cat head, yellow
lightning bolt, electric-indigo tile, and cross-platform asset pipeline. In the
running onboarding screen, the cat reads too small because the source artwork
contains generous internal whitespace and the derivation pipeline adds another
fit margin. The two pale-indigo horizontal speed trails also read as interface
lines rather than as part of the cat identity.

This refinement changes composition only. It does not redesign the cat head,
lightning bolt, background palette, tile shape, or platform coverage.

## Approved visual direction

The approved combination is **B proportion + D wave-tail**:

- enlarge the complete foreground composition by approximately 30%;
- retain an 8–10% optical safety margin around the foreground at launcher size;
- preserve the existing white cat-head and warm-yellow lightning shapes;
- horizontally center the cat-head mass on the 1024 px master, independently
  from the detached wave;
- remove both horizontal speed trails;
- add one short pale-indigo wave on the left side;
- keep the wave fully detached from the cat head with a clearly visible gap;
- use a single rounded stroke shaped like a small `~`, not a connected anatomical
  tail and not multiple speed lines;
- keep the wave subordinate to the cat head and lightning.

The detached wave uses the existing trail color `#C6CDFF`. After the final
visual refinement, its visible length is approximately 10–12% of the icon
canvas, its rounded stroke is approximately 2.4% of the canvas, and the gap to
the cat silhouette is approximately 2–3% of the canvas. It sits beside the
lower-left cheek, near the vertical center of the lightning bolt.

## Implementation approaches considered

### 1. Deterministic source normalization — selected

Preserve the existing transparent source, remove the two pale-indigo connected
components, draw the approved D wave at high resolution with antialiasing, then
normalize the complete foreground into the approved larger bounds. The existing
Pillow pipeline regenerates every platform asset from that single source.

This approach preserves the approved cat and lightning pixels, gives exact
control over spacing, and keeps all platform outputs reproducible.

### 2. Image generation edit

Ask an image model to replace the trails and reduce whitespace. This is faster
for broad exploration, but it can subtly change the ear geometry, lightning
shape, edge softness, or colors. That drift is unnecessary after the visual
direction has already been selected.

### 3. Full vector redraw

Rebuild the mark as SVG and derive raster outputs from the vector master. This
would improve long-term editability, but it is a larger identity-redraw project
and risks changing the already-approved silhouette. It is outside this focused
refinement.

## Asset pipeline

`assets/branding/speed_cat_mark.png` remains the canonical transparent 1024 px
foreground. `scripts/branding/build_icon_set.py` will own the repeatable source
normalization and continue producing:

- Flutter `brand_logo.png` and `brand_mark.png`;
- macOS launcher and template tray assets;
- iOS launcher assets;
- Android legacy launcher assets;
- Windows ICO;
- the shared full-color tray asset.

Android adaptive foreground and monochrome notification vector resources will
be updated to the same detached-wave silhouette so Android does not retain the
old horizontal trails.

## Composition and safety rules

- The cat head remains the dominant centered mass.
- The white cat-head bounding-box center must be within 1 px of the horizontal
  center of the 1024 px transparent master.
- The detached wave must not touch or overlap the cat silhouette at any output
  size.
- The detached wave must remain no wider than 120 px and no taller than 65 px
  in the 1024 px transparent master.
- No foreground pixel may be clipped by the launcher canvas.
- The detached wave must remain visible at 32 px without becoming two separate
  dots.
- At 16 px, the cat and lightning take priority; loss of fine wave curvature is
  acceptable, but clipping or merging is not.
- macOS template tray output remains monochrome and derives only from the white
  cat silhouette; the pale-indigo wave is intentionally omitted there.

## Verification

The asset validator will check:

- expected dimensions and color modes for all generated outputs;
- foreground coverage falls within the approved larger bounds;
- exactly one pale-indigo wave component exists in the transparent master;
- the wave bounding box is left of and separated from the white cat silhouette;
- launcher corners and transparent-master corners retain the required alpha;
- Windows ICO still contains all declared sizes.

Focused Flutter tests will continue asserting that onboarding, About, and the
empty-profile state use the shared `BrandMark`. After regeneration, the full
unit suite and static analysis must pass. The macOS Debug app must be rebuilt,
the old process stopped, and the new bundle launched before visual inspection of
the onboarding screen and Dock icon.

## Out of scope

- changing the indigo gradient or yellow lightning color;
- adding facial features, text, outlines, shadows on the subject, or animation;
- creating connection-state-specific tray icons;
- merging the feature branch into `main` without explicit user approval.
