# Speed Cat Centering and Tail Slimming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Center the Speed Cat head independently from its detached tail and make the tail shorter and thinner across every platform asset.

**Architecture:** Keep the immutable transparent source and deterministic Pillow asset pipeline. Translate only the white cat and yellow lightning color classes to center the cat-head bounding box, redraw one smaller antialiased wave, regenerate every raster derivative, and mirror the geometry in Android vectors.

**Tech Stack:** Python 3.9, Pillow, `unittest`, Flutter/Dart tests, Android VectorDrawable XML, Flutter macOS build.

## Global Constraints

- The white cat-head bounding-box center must be within 1 px of x=512 on the 1024 px master.
- The detached wave must remain a single `#C6CDFF` component fully separated from the cat.
- The wave bounding box must be no wider than 120 px and no taller than 65 px on the master.
- Preserve the existing white cat and yellow lightning shapes; only their horizontal position changes.
- Preserve all output dimensions, formats, platform coverage, indigo gradient, and macOS tray behavior.

---

### Task 1: Center the raster cat and slim the canonical wave

**Files:**
- Modify: `scripts/branding/test_build_icon_set.py`
- Modify: `scripts/branding/build_icon_set.py`
- Regenerate: `assets/branding/speed_cat_mark.png`
- Regenerate: `assets/images/brand_mark.png`
- Regenerate: `assets/images/brand_logo.png`
- Regenerate: all derived macOS, iOS, Android legacy, tray, and Windows icon files already owned by `build_icon_set.py`

**Interfaces:**
- Consumes: `color_class_mask(image, target) -> Image.Image` and the immutable `SOURCE_MARK_PATH`.
- Produces: `build_refined_mark(source: Image.Image) -> Image.Image` with centered cat geometry and one small detached wave.

- [ ] **Step 1: Write failing raster geometry tests**

Add assertions to the existing refined-mark tests:

```python
cat_box = build_icon_set.color_class_mask(
    self.refined,
    build_icon_set.WHITE,
).getbbox()
self.assertIsNotNone(cat_box)
assert cat_box is not None
self.assertLessEqual(abs((cat_box[0] + cat_box[2]) / 2 - 512), 1)

wave_width = wave_box[2] - wave_box[0]
wave_height = wave_box[3] - wave_box[1]
self.assertLessEqual(wave_width, 120)
self.assertLessEqual(wave_height, 65)
self.assertGreaterEqual(white_box[0] - wave_box[2], 20)
```

Update the shape-preservation test to compare sizes instead of absolute
bounding-box positions:

```python
self.assertEqual(
    (source_main.getbbox()[2] - source_main.getbbox()[0],
     source_main.getbbox()[3] - source_main.getbbox()[1]),
    (refined_main.getbbox()[2] - refined_main.getbbox()[0],
     refined_main.getbbox()[3] - refined_main.getbbox()[1]),
)
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
cd scripts/branding
python3 -m unittest test_build_icon_set.py
```

Expected: failure because the current white box is centered at x=546.5 and the
current wave is 176×94 px.

- [ ] **Step 3: Implement the centered cat and smaller wave**

In `build_refined_mark`, copy only white/yellow pixels into a fresh transparent
master at `x - 35`, preserving `y`. Draw the wave at 4× scale with:

```python
first = cubic_points(
    (110, 625),
    (128, 602),
    (148, 602),
    (164, 624),
)
second = cubic_points(
    (164, 624),
    (178, 640),
    (190, 640),
    (200, 626),
)
stroke_width = 24
```

Use rounded end caps with radius `stroke_width // 2`. Leave the existing icon
fit ratios unchanged.

- [ ] **Step 4: Regenerate and verify GREEN**

Run:

```bash
python3 scripts/branding/build_icon_set.py
cd scripts/branding
python3 -m unittest test_build_icon_set.py
```

Expected: all refined-mark tests pass.

- [ ] **Step 5: Commit raster implementation**

```bash
git add -u
git add assets/branding/speed_cat_mark.png assets/images
git commit -m "fix: center Speed Cat and slim wave tail"
```

### Task 2: Strengthen generated-asset validation

**Files:**
- Modify: `scripts/branding/test_validate_brand_assets.py`
- Modify: `scripts/branding/validate_brand_assets.py`

**Interfaces:**
- Consumes: canonical `brand_mark.png`.
- Produces: `brand_mark_geometry_errors(mark: Image.Image) -> list[str]` that rejects off-center cats and oversized waves.

- [ ] **Step 1: Add failing validator tests**

Add a test that loads the source and expects an off-center error, and tighten
the accepted wave rules:

```python
def test_off_center_cat_is_rejected(self) -> None:
    source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")
    errors = validate_brand_assets.brand_mark_geometry_errors(source)
    self.assertTrue(
        any("cat head must be horizontally centered" in error for error in errors)
    )
```

- [ ] **Step 2: Run the validator tests and confirm RED**

Run:

```bash
cd scripts/branding
python3 -m unittest test_validate_brand_assets.py
```

Expected: failure because the validator does not yet report cat centering.

- [ ] **Step 3: Implement exact validator bounds**

Add these checks to `brand_mark_geometry_errors`:

```python
cat_center_x = (white_box[0] + white_box[2]) / 2
if abs(cat_center_x - rgba_mark.width / 2) > 1:
    geometry_errors.append(
        f"cat head must be horizontally centered: {cat_center_x}"
    )
wave_width = wave_box[2] - wave_box[0]
wave_height = wave_box[3] - wave_box[1]
if wave_width > 120 or wave_height > 65:
    geometry_errors.append(
        f"detached wave is too large: {wave_width}x{wave_height}"
    )
if white_box[0] - wave_box[2] < 20:
    geometry_errors.append("detached wave must keep a clear gap")
```

- [ ] **Step 4: Verify validator GREEN**

Run:

```bash
cd scripts/branding
python3 -m unittest test_validate_brand_assets.py
cd ../..
python3 scripts/branding/validate_brand_assets.py
```

Expected: all tests pass and 32 raster assets plus the Windows ICO validate.

- [ ] **Step 5: Commit validation**

```bash
git add scripts/branding/test_validate_brand_assets.py scripts/branding/validate_brand_assets.py
git commit -m "test: enforce centered Speed Cat geometry"
```

### Task 3: Match the Android vectors

**Files:**
- Modify: `test/branding/android_icon_resources_test.dart`
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Modify: `android/app/src/main/res/drawable/ic_stat_logo.xml`

**Interfaces:**
- Consumes: approved centered-cat/small-wave geometry.
- Produces: adaptive launcher and notification vectors with one short, thin detached curve.

- [ ] **Step 1: Tighten Android resource expectations**

Require the launcher wave path and stroke:

```dart
expect(
  foreground,
  contains('M11.5,62 C13,60.2 15,60.2 16.5,62 '
      'C17.5,63.2 18.5,63.2 19.2,62.4'),
);
expect(foreground, contains('android:strokeWidth="2.2"'));
```

Require the notification path and stroke:

```dart
expect(
  notification,
  contains('M2.2,14 C2.7,13.3 3.3,13.3 3.8,14 '
      'C4.1,14.4 4.4,14.4 4.6,14.1'),
);
expect(notification, contains('android:strokeWidth="0.7"'));
```

- [ ] **Step 2: Run focused Flutter test and confirm RED**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
```

Expected: failure because the old larger path and stroke remain.

- [ ] **Step 3: Replace both Android wave paths**

Use the exact path and stroke strings asserted above; keep the existing cat and
lightning paths unchanged.

- [ ] **Step 4: Verify Android resources GREEN**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
xmllint --noout android/app/src/main/res/drawable/ic_launcher_foreground.xml
xmllint --noout android/app/src/main/res/drawable/ic_stat_logo.xml
```

Expected: test and both XML parses pass.

- [ ] **Step 5: Commit Android vector update**

```bash
git add test/branding/android_icon_resources_test.dart \
  android/app/src/main/res/drawable/ic_launcher_foreground.xml \
  android/app/src/main/res/drawable/ic_stat_logo.xml
git commit -m "fix: slim Android Speed Cat tail"
```

### Task 4: Verify, rebuild, and refresh the running app

**Files:**
- Verify only: repository tests and generated app bundle.

**Interfaces:**
- Consumes: committed raster and Android geometry.
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

Expected: six Python tests pass, asset validation passes, Flutter analysis has
no issues, 731 Flutter tests pass with one skipped, and diff check is empty.

- [ ] **Step 2: Build and verify the macOS bundle**

```bash
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: build and signature verification exit 0.

- [ ] **Step 3: Replace the running process**

Resolve the exact existing ClashMiao PID, terminate it normally, then launch:

```bash
open build/macos/Build/Products/Debug/clashmiao.app
```

Confirm the only executable path is inside this worktree's Debug bundle.

- [ ] **Step 4: Inspect the real onboarding screen**

Use Computer Use to capture the running app. Confirm:

- cat head is horizontally centered in the tile;
- wave is visibly shorter and thinner than the prior D revision;
- wave remains detached;
- no old two-line logo or stale process is visible.

- [ ] **Step 5: Commit any final visual correction**

If inspection requires no correction, do not create an empty commit. If a
correction is needed, repeat the focused RED/GREEN test before changing the
asset generator, then commit:

```bash
git add -u
git commit -m "fix: polish centered Speed Cat mark"
```
