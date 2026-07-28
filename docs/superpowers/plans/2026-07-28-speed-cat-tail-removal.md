# Speed Cat Tail Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the detached wave tail from every Speed Cat asset while preserving the centered cat, lightning, scale, and indigo tile.

**Architecture:** Keep the immutable source and existing color-class pipeline. `build_refined_mark` discards source trail pixels, shifts the cat and lightning into the approved centered position, and returns without drawing replacement geometry; the normal generator then rebuilds every raster derivative. Android's two vector resources remove their independent stroked paths.

**Tech Stack:** Python 3.9, Pillow, `unittest`, Flutter/Dart tests, Android VectorDrawable XML, Flutter macOS build.

## Global Constraints

- The canonical mark contains zero pixels classified as `#C6CDFF`.
- The white cat-head bounding-box center remains within 1 px of x=512.
- The cat silhouette, lightning, foreground scale, indigo gradient, output dimensions, and platform coverage remain unchanged.
- Android launcher and notification vectors contain no detached stroked path.

---

### Task 1: Make the canonical raster mark tailless

**Files:**
- Modify: `scripts/branding/test_build_icon_set.py`
- Modify: `scripts/branding/build_icon_set.py`
- Regenerate: `assets/branding/speed_cat_mark.png`
- Regenerate: `assets/images/brand_mark.png`
- Regenerate: `assets/images/brand_logo.png`
- Regenerate: existing macOS, iOS, Android legacy, tray, and Windows outputs owned by `build_icon_set.py`

**Interfaces:**
- Consumes: `SOURCE_MARK_PATH`, `color_class_mask(image, target)`.
- Produces: `build_refined_mark(source: Image.Image) -> Image.Image` containing only the centered cat and lightning.

- [ ] **Step 1: Replace the wave test with a failing zero-trail test**

In `test_build_icon_set.py`, replace
`test_refinement_replaces_two_lines_with_one_detached_wave` with:

```python
def test_refinement_removes_all_trail_pixels(self) -> None:
    trail = build_icon_set.color_class_mask(
        self.refined,
        build_icon_set.TRAIL,
    )

    self.assertIsNone(trail.getbbox())
    self.assertEqual(
        build_icon_set.connected_component_count(trail),
        0,
    )
```

Keep the existing cat-centering and shape-preservation tests unchanged.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
cd scripts/branding
python3 -m unittest test_build_icon_set.py
```

Expected: failure because the current refined mark still contains one trail
component.

- [ ] **Step 3: Remove replacement-wave drawing from production**

In `build_icon_set.py`:

- keep `TRAIL` in `PALETTE` so source trail pixels can still be classified and
  discarded;
- keep `CAT_HORIZONTAL_OFFSET = -35`;
- delete `WAVE_STROKE_WIDTH`;
- delete `cubic_points`;
- delete the high-resolution wave canvas, Bézier points, rounded line, end caps,
  and final wave composite from `build_refined_mark`;
- return `refined` immediately after the centered non-trail pixels are copied.

- [ ] **Step 4: Regenerate and verify GREEN**

Run:

```bash
python3 scripts/branding/build_icon_set.py
(cd scripts/branding && python3 -m unittest test_build_icon_set.py)
```

Expected: four tests pass and the generated canonical mark has no trail-color
bounding box.

- [ ] **Step 5: Commit the raster change**

```bash
git add -u
git commit -m "fix: remove Speed Cat tail from raster assets"
```

### Task 2: Enforce zero trail pixels in asset validation

**Files:**
- Modify: `scripts/branding/test_validate_brand_assets.py`
- Modify: `scripts/branding/validate_brand_assets.py`

**Interfaces:**
- Consumes: a canonical RGBA mark.
- Produces: `brand_mark_geometry_errors(mark: Image.Image) -> list[str]` that accepts a centered tailless mark and rejects any trail-color component.

- [ ] **Step 1: Write failing validator behavior**

Rename the accepted-mark test to
`test_tailless_refined_mark_is_accepted`. Change the old-source test to:

```python
def test_source_with_trails_is_rejected(self) -> None:
    source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")

    errors = validate_brand_assets.brand_mark_geometry_errors(source)

    self.assertIn("brand mark must not contain trail pixels", errors)
```

Replace the oversized-wave test with a single-component mutation test:

```python
def test_any_detached_trail_component_is_rejected(self) -> None:
    mark = Image.new("RGBA", (1024, 1024))
    draw = ImageDraw.Draw(mark)
    draw.rectangle((312, 250, 712, 774), fill=(*build_icon_set.WHITE, 255))
    draw.ellipse((100, 600, 120, 620), fill=(*build_icon_set.TRAIL, 255))

    errors = validate_brand_assets.brand_mark_geometry_errors(mark)

    self.assertIn("brand mark must not contain trail pixels", errors)
```

- [ ] **Step 2: Run validator tests and confirm RED**

Run:

```bash
cd scripts/branding
python3 -m unittest test_validate_brand_assets.py
```

Expected: failure because the validator still requires one wave and does not
emit the zero-trail error.

- [ ] **Step 3: Simplify `brand_mark_geometry_errors`**

Use independent cat and trail checks:

```python
wave_box = color_class_mask(rgba_mark, TRAIL).getbbox()
white_box = color_class_mask(rgba_mark, WHITE).getbbox()
geometry_errors: list[str] = []

if white_box is None:
    return ["brand mark must contain cat"]
if wave_box is not None:
    geometry_errors.append("brand mark must not contain trail pixels")

cat_center_x = (white_box[0] + white_box[2]) / 2
if abs(cat_center_x - rgba_mark.width / 2) > 1:
    geometry_errors.append(
        f"cat head must be horizontally centered: {cat_center_x}"
    )
return geometry_errors
```

Delete component-count, size, spacing, and wave-position requirements from this
validator.

- [ ] **Step 4: Verify validator GREEN**

Run:

```bash
(cd scripts/branding && python3 -m unittest test_validate_brand_assets.py)
python3 scripts/branding/validate_brand_assets.py
```

Expected: five tests pass and all 32 raster assets plus the Windows ICO
validate.

- [ ] **Step 5: Commit validation**

```bash
git add scripts/branding/test_validate_brand_assets.py \
  scripts/branding/validate_brand_assets.py
git commit -m "test: reject Speed Cat tail pixels"
```

### Task 3: Remove Android vector tails

**Files:**
- Modify: `test/branding/android_icon_resources_test.dart`
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Modify: `android/app/src/main/res/drawable/ic_stat_logo.xml`

**Interfaces:**
- Consumes: the final tailless visual direction.
- Produces: an adaptive foreground with exactly two filled paths and a notification icon with exactly one filled path.

- [ ] **Step 1: Write failing Android resource assertions**

Replace wave-specific expectations with:

```dart
expect(
  RegExp(r'<path\\b').allMatches(foreground).length,
  2,
);
expect(foreground, isNot(contains('android:stroke')));

expect(
  RegExp(r'<path\\b').allMatches(notification).length,
  1,
);
expect(notification, isNot(contains('android:stroke')));
```

Keep the adaptive-resource references, viewport, `evenOdd`, and old-template
regression checks.

- [ ] **Step 2: Run focused Flutter test and confirm RED**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
```

Expected: failure because each vector still contains an extra stroked tail
path.

- [ ] **Step 3: Delete the tail paths**

Remove the final transparent/stroked `<path>` element from both XML files.
Leave both launcher fill paths and the notification fill path byte-for-byte
unchanged.

- [ ] **Step 4: Verify Android resources GREEN**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
xmllint --noout android/app/src/main/res/drawable/ic_launcher_foreground.xml
xmllint --noout android/app/src/main/res/drawable/ic_stat_logo.xml
```

Expected: the Flutter test and both XML parses pass.

- [ ] **Step 5: Commit Android removal**

```bash
git add test/branding/android_icon_resources_test.dart \
  android/app/src/main/res/drawable/ic_launcher_foreground.xml \
  android/app/src/main/res/drawable/ic_stat_logo.xml
git commit -m "fix: remove Speed Cat tail from Android vectors"
```

### Task 4: Verify and refresh the macOS application

**Files:**
- Verify only: repository tests and generated Debug bundle.

**Interfaces:**
- Consumes: committed tailless assets.
- Produces: a signed macOS Debug bundle running as the only ClashMiao process.

- [ ] **Step 1: Run complete verification**

```bash
(cd scripts/branding && python3 -m unittest \
  test_build_icon_set.py test_validate_brand_assets.py)
python3 scripts/branding/validate_brand_assets.py
flutter analyze
bash bin/test-unit.sh
git diff --check
```

Expected: nine Python tests pass, asset validation passes, Flutter analysis has
no issues, 731 Flutter tests pass with one skipped, and diff check is empty.

- [ ] **Step 2: Build and verify the macOS bundle**

```bash
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: both commands exit 0.

- [ ] **Step 3: Replace the running process**

Resolve the exact ClashMiao PID, terminate it normally, launch the Debug bundle,
and confirm that the only running executable is:

```text
/Users/lideqian/code/clashmiao/.worktrees/logo-redesign/build/macos/Build/Products/Debug/clashmiao.app/Contents/MacOS/clashmiao
```

- [ ] **Step 4: Inspect the real application**

Use Computer Use to capture the running onboarding screen. Confirm:

- only the centered cat and lightning appear;
- no pale-indigo tail, line, dot, or residue remains;
- the cat size and tile are unchanged;
- no stale application process is visible.

- [ ] **Step 5: Commit any required visual correction**

If inspection finds a defect, first add a focused failing test, then correct,
regenerate, verify, and commit:

```bash
git add -u
git commit -m "fix: polish tailless Speed Cat mark"
```

If inspection finds no defect, do not create an empty commit.
