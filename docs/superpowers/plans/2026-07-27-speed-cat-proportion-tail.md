# Speed Cat Proportion and Wave-Tail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enlarge the Speed Cat foreground by approximately 30% and replace the two horizontal trails with the approved detached D-shaped pale-indigo wave across every branded platform surface.

**Architecture:** Preserve the approved cat and lightning pixels by treating the current transparent mark as an immutable source asset. Extend the Pillow pipeline with deterministic color-class removal, antialiased Bézier wave drawing, and larger platform fit ratios; regenerate all raster outputs from the refined canonical mark and update Android vectors separately.

**Tech Stack:** Python 3 + Pillow 11+, Flutter 3.44+, Dart 3.12+, Android VectorDrawable XML, Xcode asset catalogs, Windows ICO.

## Global Constraints

- Use the approved **B proportion + D wave-tail** composition.
- Preserve the white cat head, yellow lightning, electric-indigo gradient, and rounded tile.
- Remove both horizontal trails and add exactly one short `#C6CDFF` wave.
- The wave must remain fully detached from the cat with a visible 3–4% canvas gap.
- The wave must remain subordinate to the cat and lightning and readable at 32 px.
- Keep macOS template tray output cat-only and monochrome.
- Do not merge `codex/logo-redesign` into `main` without explicit user approval.

---

### Task 1: Deterministic refined foreground

**Files:**
- Create: `assets/branding/speed_cat_mark_source.png`
- Create: `scripts/branding/test_build_icon_set.py`
- Modify: `scripts/branding/build_icon_set.py`
- Modify: `assets/branding/speed_cat_mark.png`

**Interfaces:**
- Consumes: the current 1024×1024 RGBA mark copied to `assets/branding/speed_cat_mark_source.png`.
- Produces: `build_refined_mark(source: Image.Image) -> Image.Image`, a repeatable 1024×1024 RGBA canonical foreground containing the unchanged cat/lightning plus exactly one detached D wave.
- Produces: `color_class_mask(image: Image.Image, target: tuple[int, int, int]) -> Image.Image`, used by tests and validation to identify brand palette components.
- Produces: `connected_component_count(mask: Image.Image, threshold: int = 32) -> int`, used to prove that the pale-indigo geometry is one continuous wave.

- [ ] **Step 1: Preserve the approved v1 pixels as an immutable input**

Run:

```bash
cp assets/branding/speed_cat_mark.png \
  assets/branding/speed_cat_mark_source.png
```

Expected: both files have identical MD5 hashes before refinement.

- [ ] **Step 2: Write failing refinement tests**

Create `scripts/branding/test_build_icon_set.py`:

```python
#!/usr/bin/env python3

from __future__ import annotations

import unittest

from PIL import Image

import build_icon_set


class RefinedMarkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = Image.open(build_icon_set.SOURCE_MARK_PATH).convert("RGBA")
        cls.refined = build_icon_set.build_refined_mark(cls.source)

    def test_refinement_preserves_canvas_and_transparency(self) -> None:
        self.assertEqual(self.refined.size, (1024, 1024))
        self.assertEqual(self.refined.mode, "RGBA")
        self.assertEqual(self.refined.getpixel((0, 0))[3], 0)

    def test_refinement_keeps_cat_and_lightning_pixels(self) -> None:
        source_main = build_icon_set.color_class_mask(
            self.source,
            build_icon_set.WHITE,
        )
        refined_main = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        )
        self.assertEqual(source_main.getbbox(), refined_main.getbbox())

        source_bolt = build_icon_set.color_class_mask(
            self.source,
            build_icon_set.YELLOW,
        )
        refined_bolt = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.YELLOW,
        )
        self.assertEqual(source_bolt.getbbox(), refined_bolt.getbbox())

    def test_refinement_replaces_two_lines_with_one_detached_wave(self) -> None:
        wave = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.TRAIL,
        )
        wave_box = wave.getbbox()
        white_box = build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        ).getbbox()

        self.assertIsNotNone(wave_box)
        self.assertIsNotNone(white_box)
        assert wave_box is not None
        assert white_box is not None
        self.assertEqual(build_icon_set.connected_component_count(wave), 1)
        self.assertGreaterEqual(wave_box[0], 90)
        self.assertLessEqual(wave_box[2], 270)
        self.assertGreaterEqual(white_box[0] - wave_box[2], 8)
        self.assertLessEqual(wave_box[3] - wave_box[1], 100)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
python3 scripts/branding/test_build_icon_set.py
```

Expected: import or attribute failures because `SOURCE_MARK_PATH`,
`build_refined_mark`, palette constants, and `color_class_mask` do not exist.

- [ ] **Step 4: Implement palette classification and the antialiased D wave**

In `scripts/branding/build_icon_set.py`, add:

```python
SOURCE_MARK_PATH = ROOT / "assets/branding/speed_cat_mark_source.png"
MARK_PATH = ROOT / "assets/branding/speed_cat_mark.png"

WHITE = (255, 255, 255)
YELLOW = (255, 215, 94)
TRAIL = (198, 205, 255)
PALETTE = (WHITE, YELLOW, TRAIL)

MAC_MARK_RATIO = 1.04
SQUARE_MARK_RATIO = 1.12


def nearest_brand_color(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(PALETTE, key=lambda target: color_distance(rgb, target))


def color_class_mask(
    image: Image.Image,
    target: tuple[int, int, int],
) -> Image.Image:
    source = image.convert("RGBA")
    mask = Image.new("L", source.size)
    source_pixels = source.load()
    mask_pixels = mask.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha >= 32 and nearest_brand_color((red, green, blue)) == target:
                mask_pixels[x, y] = alpha
    return mask


def connected_component_count(
    mask: Image.Image,
    threshold: int = 32,
) -> int:
    pixels = mask.convert("L").load()
    width, height = mask.size
    seen: set[tuple[int, int]] = set()
    count = 0
    for y in range(height):
        for x in range(width):
            if pixels[x, y] < threshold or (x, y) in seen:
                continue
            count += 1
            pending = [(x, y)]
            seen.add((x, y))
            while pending:
                current_x, current_y = pending.pop()
                for neighbor in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    neighbor_x, neighbor_y = neighbor
                    if not (0 <= neighbor_x < width and 0 <= neighbor_y < height):
                        continue
                    if neighbor in seen or pixels[neighbor_x, neighbor_y] < threshold:
                        continue
                    seen.add(neighbor)
                    pending.append(neighbor)
    return count


def cubic_points(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    steps: int = 48,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(steps + 1):
        t = index / steps
        inverse = 1 - t
        x = (
            inverse**3 * start[0]
            + 3 * inverse**2 * t * control_a[0]
            + 3 * inverse * t**2 * control_b[0]
            + t**3 * end[0]
        )
        y = (
            inverse**3 * start[1]
            + 3 * inverse**2 * t * control_a[1]
            + 3 * inverse * t**2 * control_b[1]
            + t**3 * end[1]
        )
        points.append((x, y))
    return points


def build_refined_mark(source: Image.Image) -> Image.Image:
    source = source.convert("RGBA")
    keep_mask = ImageChops.lighter(
        color_class_mask(source, WHITE),
        color_class_mask(source, YELLOW),
    )
    refined = Image.new("RGBA", source.size)
    refined.paste(source, mask=keep_mask)

    scale = 4
    wave = Image.new(
        "RGBA",
        (source.width * scale, source.height * scale),
    )
    first = cubic_points(
        (110, 620),
        (140, 580),
        (170, 580),
        (195, 620),
    )
    second = cubic_points(
        (195, 620),
        (215, 650),
        (235, 650),
        (245, 625),
    )
    points = [
        (round(x * scale), round(y * scale))
        for x, y in first + second[1:]
    ]
    ImageDraw.Draw(wave).line(
        points,
        fill=(*TRAIL, 255),
        width=40 * scale,
        joint="curve",
    )
    radius = 20 * scale
    draw = ImageDraw.Draw(wave)
    for x, y in (points[0], points[-1]):
        draw.ellipse(
            (x - radius, y - radius, x + radius, y + radius),
            fill=(*TRAIL, 255),
        )
    wave = wave.resize(source.size, RESAMPLE)
    refined.alpha_composite(wave)
    return refined
```

Update `main()` to load `SOURCE_MARK_PATH`, call `build_refined_mark`, save the
result to `MARK_PATH`, then derive all platform outputs from that returned image.
Replace `ratio=0.80` with `MAC_MARK_RATIO` and `ratio=0.86` with
`SQUARE_MARK_RATIO`.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run:

```bash
python3 scripts/branding/test_build_icon_set.py
```

Expected: 3 tests pass.

- [ ] **Step 6: Generate the canonical mark and all raster derivatives**

Run:

```bash
python3 scripts/branding/build_icon_set.py
```

Expected: `assets/branding/speed_cat_mark.png` now has one pale-indigo wave;
macOS, iOS, Android legacy, Windows, Flutter, and tray raster files are updated.

- [ ] **Step 7: Commit the deterministic foreground pipeline**

```bash
git add \
  assets/branding/speed_cat_mark_source.png \
  assets/branding/speed_cat_mark.png \
  assets/images \
  macos/Runner/Assets.xcassets/AppIcon.appiconset \
  ios/Runner/Assets.xcassets/AppIcon.appiconset \
  android/app/src/main/res/mipmap-mdpi/ic_launcher.png \
  android/app/src/main/res/mipmap-hdpi/ic_launcher.png \
  android/app/src/main/res/mipmap-xhdpi/ic_launcher.png \
  android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png \
  android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png \
  windows/runner/resources/app_icon.ico \
  scripts/branding/build_icon_set.py \
  scripts/branding/test_build_icon_set.py
git commit -m "feat: enlarge Speed Cat with detached wave tail"
```

---

### Task 2: Brand geometry validation

**Files:**
- Modify: `scripts/branding/validate_brand_assets.py`

**Interfaces:**
- Consumes: `color_class_mask` and palette constants from `build_icon_set.py`.
- Produces: command-line validation that rejects the old small/two-trail composition and accepts only the approved larger/single-wave geometry.

- [ ] **Step 1: Add geometry checks before regenerating accepted assets**

Import the shared helpers:

```python
from build_icon_set import (
    TRAIL,
    WHITE,
    color_class_mask,
    connected_component_count,
)
```

After the existing `brand_mark` transparency check, add:

```python
if brand_mark is not None:
    with brand_mark.convert("RGBA") as rgba_mark:
        wave_box = color_class_mask(rgba_mark, TRAIL).getbbox()
        white_box = color_class_mask(rgba_mark, WHITE).getbbox()
        if wave_box is None or white_box is None:
            errors.append("brand mark must contain cat and detached wave")
        elif connected_component_count(
            color_class_mask(rgba_mark, TRAIL)
        ) != 1:
            errors.append("brand mark must contain exactly one wave component")
        elif white_box[0] - wave_box[2] < 8:
            errors.append("detached wave must not touch the cat")
        elif not (90 <= wave_box[0] and wave_box[2] <= 270):
            errors.append(f"unexpected detached wave bounds: {wave_box}")
```

For the final Flutter tile, classify the white cat and enforce B coverage:

```python
brand_logo = image_at("assets/images/brand_logo.png")
if brand_logo is not None:
    with brand_logo.convert("RGBA") as rgba_logo:
        white_box = color_class_mask(rgba_logo, WHITE).getbbox()
        if white_box is None:
            errors.append("brand logo must contain white cat")
        else:
            width = white_box[2] - white_box[0]
            if not 520 <= width <= 610:
                errors.append(f"brand logo cat width outside B range: {width}")
```

- [ ] **Step 2: Verify the validator passes refined outputs**

Run:

```bash
python3 scripts/branding/validate_brand_assets.py
```

Expected: `validated 32 raster assets and Windows ICO`.

- [ ] **Step 3: Prove the validator rejects the old composition**

Run a one-off Python check that calls the same geometry helpers on
`assets/branding/speed_cat_mark_source.png`:

```bash
python3 - <<'PY'
from PIL import Image
from scripts.branding.build_icon_set import TRAIL, color_class_mask

source = Image.open("assets/branding/speed_cat_mark_source.png").convert("RGBA")
box = color_class_mask(source, TRAIL).getbbox()
assert box is not None
assert box[2] > 270 or box[0] < 90, box
print("old two-trail geometry rejected:", box)
PY
```

Expected: prints the old trail bounding box and exits 0.

- [ ] **Step 4: Commit validator coverage**

```bash
git add scripts/branding/validate_brand_assets.py
git commit -m "test: validate Speed Cat wave-tail geometry"
```

---

### Task 3: Android adaptive and notification vectors

**Files:**
- Modify: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Modify: `android/app/src/main/res/drawable/ic_stat_logo.xml`
- Modify: `test/branding/android_icon_resources_test.dart`

**Interfaces:**
- Consumes: the approved detached single-wave geometry.
- Produces: adaptive launcher and monochrome notification vectors with exactly one rounded, detached wave path.

- [ ] **Step 1: Strengthen the Android resource test**

Replace the current notification-only shape assertions with:

```dart
final foreground = File(
  'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
).readAsStringSync();
expect(foreground, contains('android:strokeColor="#FFC6CDFF"'));
expect(foreground, contains('android:strokeLineCap="round"'));
expect(foreground, contains('M15,62 C18,58 21,58 24,62'));
expect(foreground, isNot(contains('M24,51 C17,51')));
expect(foreground, isNot(contains('M25,64 C17,67')));

final notification = File(
  'android/app/src/main/res/drawable/ic_stat_logo.xml',
).readAsStringSync();
expect(notification, contains('android:viewportWidth="24"'));
expect(notification, contains('android:strokeLineCap="round"'));
expect(notification, contains('android:strokeWidth="1.2"'));
```

- [ ] **Step 2: Run the Android resource test and verify RED**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
```

Expected: failures because adaptive foreground still contains two trail
subpaths and notification vector has no detached wave stroke.

- [ ] **Step 3: Replace Android vectors with one detached wave**

In `ic_launcher_foreground.xml`, replace the current two-subpath trail with:

```xml
<path
    android:fillColor="@android:color/transparent"
    android:pathData="M15,62 C18,58 21,58 24,62 C26,65 28,65 29,63"
    android:strokeColor="#FFC6CDFF"
    android:strokeLineCap="round"
    android:strokeWidth="4" />
```

In `ic_stat_logo.xml`, append:

```xml
<path
    android:fillColor="@android:color/transparent"
    android:pathData="M2.8,14 C3.6,12.9 4.4,12.9 5.2,14 C5.7,14.8 6.2,14.8 6.5,14.3"
    android:strokeColor="#FFFFFFFF"
    android:strokeLineCap="round"
    android:strokeWidth="1.2" />
```

- [ ] **Step 4: Verify XML and focused test GREEN**

Run:

```bash
xmllint --noout \
  android/app/src/main/res/drawable/ic_launcher_foreground.xml \
  android/app/src/main/res/drawable/ic_stat_logo.xml
flutter test test/branding/android_icon_resources_test.dart
```

Expected: XML validation succeeds and the Flutter test passes.

- [ ] **Step 5: Commit Android vector refinement**

```bash
git add \
  android/app/src/main/res/drawable/ic_launcher_foreground.xml \
  android/app/src/main/res/drawable/ic_stat_logo.xml \
  test/branding/android_icon_resources_test.dart
git commit -m "feat: align Android icons with wave-tail mark"
```

---

### Task 4: Full verification and running-app refresh

**Files:**
- Verify: all files changed in Tasks 1–3.
- Runtime artifact: `build/macos/Build/Products/Debug/clashmiao.app`

**Interfaces:**
- Consumes: final generated assets and Android vectors.
- Produces: a clean branch, passing checks, a signed macOS Debug app, and one running process from the `logo-redesign` worktree.

- [ ] **Step 1: Run formatting and focused brand checks**

```bash
dart format test/branding/android_icon_resources_test.dart
python3 scripts/branding/test_build_icon_set.py
python3 scripts/branding/validate_brand_assets.py
flutter test \
  test/branding/android_icon_resources_test.dart \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart
```

Expected: all commands exit 0.

- [ ] **Step 2: Run project-wide verification**

```bash
flutter analyze
bash bin/test-unit.sh
git diff --check
```

Expected: static analysis reports no issues; the complete unit suite reports no
failures; diff check is clean.

- [ ] **Step 3: Build macOS with the local core**

```bash
test -f libcore/bin/libcore.dylib
lipo -archs libcore/bin/libcore.dylib
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: `libcore.dylib` reports `x86_64 arm64`; build and signature checks
exit 0.

- [ ] **Step 4: Restore build-only CocoaPods metadata if needed**

If `git diff -- macos/Podfile.lock` shows only `COCOAPODS: 1.17.0`, restore that
line to the committed `COCOAPODS: 1.16.2` with `apply_patch`. Do not discard
other user changes.

- [ ] **Step 5: Stop every old ClashMiao instance and launch the new bundle**

First list exact process paths:

```bash
ps -axo pid,lstart,command | rg '[c]lashmiao.app/Contents/MacOS/clashmiao'
```

Send `TERM` only to listed ClashMiao PIDs, wait for their normal shutdown, then:

```bash
open -n \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: exactly one `clashmiao` process remains and its executable path begins
with `/Users/lideqian/code/clashmiao/.worktrees/logo-redesign/`.

- [ ] **Step 6: Visually verify the onboarding window**

Use Computer Use to inspect the running worktree app. Confirm:

- the cat head is visibly larger than the previous running screenshot;
- the old two horizontal trails are absent;
- one small detached pale-indigo D wave appears at the lower-left of the cat;
- the wave does not touch the cat;
- no icon edge is clipped.

Capture the verified app screenshot and report it to the user.

- [ ] **Step 7: Commit any final polish required by verification**

If visual verification requires a bounded geometry correction, rerun Tasks 1–4
checks. Stage the changed generator, generated raster assets, Android vectors,
and validators using the explicit file lists from Tasks 1–3, then commit:

```bash
git commit -m "fix: polish Speed Cat wave-tail geometry"
```

If no correction is needed, do not create an empty commit.
