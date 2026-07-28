# ClashMiao Logo Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every Flutter/paw placeholder with the approved Speed Cat identity across platform launchers, system trays, Android notifications, onboarding, About, and the empty-profile state.

**Architecture:** Generate one flat 1024 px Speed Cat source with ImageGen, remove its chroma-key background, and use a checked-in Pillow pipeline to derive platform-specific raster assets without visual drift. Flutter consumes two shared in-app assets through a focused `BrandMark` widget; platform launchers and tray/notification resources remain native to each platform.

**Tech Stack:** Flutter 3.44+, Dart 3.12+, Python 3 + Pillow 11+, ImageGen built-in tool, Xcode asset catalogs, Android adaptive-icon resources, Windows ICO.

## Global Constraints

- Full-color palette: upper-left `#7667FF`, lower-right `#3155D8`, bolt `#FFD75E`, white cat silhouette.
- The mark contains no words, letters, facial features, fur, shield, globe, or generic VPN symbol.
- iOS marketing artwork is opaque and square; macOS artwork has transparent outer corners.
- Android adaptive foreground stays inside the adaptive-icon safe zone.
- macOS tray rendering uses an alpha-only template image with `isTemplate: true`.
- Windows/Linux use a simplified full-color tray image.
- Onboarding, About, and empty profiles consume the same shared `BrandMark` component.
- Do not change page copy, layout constraints, app name, or unrelated theme behavior.

---

### Task 1: Generate and validate the canonical brand assets

**Files:**
- Create: `assets/branding/speed_cat_mark.png`
- Create: `assets/images/brand_logo.png`
- Create: `assets/images/brand_mark.png`
- Create: `assets/images/tray_icon_macos.png`
- Modify: `assets/images/tray_icon.png`
- Create: `scripts/branding/build_icon_set.py`
- Create: `scripts/branding/validate_brand_assets.py`
- Modify: `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- Modify: `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- Modify: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Modify: `windows/runner/resources/app_icon.ico`

**Interfaces:**
- Consumes: a transparent 1024×1024 RGBA Speed Cat foreground at `assets/branding/speed_cat_mark.png`.
- Produces: `brand_logo.png` (rounded tile), `brand_mark.png` (transparent foreground), two tray variants, all existing platform launcher filenames, and a multi-resolution ICO.

- [ ] **Step 1: Add a failing asset-contract validator**

Create `scripts/branding/validate_brand_assets.py` with the exact size and alpha checks:

```python
#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "assets/branding/speed_cat_mark.png": (1024, 1024),
    "assets/images/brand_logo.png": (1024, 1024),
    "assets/images/brand_mark.png": (1024, 1024),
    "assets/images/tray_icon.png": (128, 128),
    "assets/images/tray_icon_macos.png": (128, 128),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": (32, 32),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": (64, 64),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": (128, 128),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": (256, 256),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": (512, 512),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": (1024, 1024),
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (1024, 1024),
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
}
EXPECTED.update({
    f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}": (size, size)
    for filename, size in IOS.items()
})

errors: list[str] = []
for relative, expected_size in EXPECTED.items():
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing: {relative}")
        continue
    with Image.open(path) as image:
        if image.size != expected_size:
            errors.append(f"{relative}: expected {expected_size}, got {image.size}")

with Image.open(ROOT / "assets/images/brand_mark.png") as image:
    if image.mode != "RGBA" or image.getpixel((0, 0))[3] != 0:
        errors.append("brand_mark.png must have transparent RGBA corners")

with Image.open(
    ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
) as image:
    if image.mode != "RGBA" or image.getpixel((0, 0))[3] != 0:
        errors.append("macOS 1024 icon must have transparent outer corners")

with Image.open(
    ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
) as image:
    if image.convert("RGBA").getpixel((0, 0))[3] != 255:
        errors.append("iOS marketing icon must be opaque")

with Image.open(ROOT / "windows/runner/resources/app_icon.ico") as image:
    sizes = set(image.info.get("sizes", set()))
    required = {(16, 16), (32, 32), (48, 48), (128, 128), (256, 256)}
    if not required.issubset(sizes):
        errors.append(f"Windows ICO missing sizes: {sorted(required - sizes)}")

if errors:
    raise SystemExit("\n".join(errors))
print(f"validated {len(EXPECTED)} raster assets and Windows ICO")
```

- [ ] **Step 2: Run the validator and confirm the new contract fails**

Run:

```bash
python3 scripts/branding/validate_brand_assets.py
```

Expected: non-zero exit with missing `assets/branding/speed_cat_mark.png`,
`assets/images/brand_logo.png`, and `assets/images/tray_icon_macos.png`.

- [ ] **Step 3: Generate the ImageGen source**

Use the built-in ImageGen tool with this prompt:

```text
Use case: logo-brand
Asset type: master app logo foreground for a cross-platform proxy client named ClashMiao / 喵速
Primary request: create a bold Speed Cat symbol combining a simplified white cat-head silhouette, a warm yellow lightning bolt cut into its center, and exactly two short pale-indigo speed trails on the left
Scene/backdrop: perfectly flat solid #00ff00 chroma-key background for removal
Style/medium: premium flat vector-style brand mark, geometric curves, crisp edges, no outlines
Composition/framing: centered square composition, generous 18% padding, symmetrical cat ears, lightning angled forward, readable at 16 px
Color palette: cat #FFFFFF, bolt #FFD75E, speed trails #C6CDFF
Constraints: the background is one uniform #00ff00 with no texture, gradient, floor, shadow, or lighting variation; no text; no watermark; no facial features; no fur; no shield; no globe; no extra symbols
Avoid: photorealism, 3D rendering, mascots with eyes, typography, tiny details, cast shadows, reflections
```

Copy the selected output to `tmp/imagegen/speed_cat_chroma.png`, remove the
background with:

```bash
python /Users/lideqian/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py \
  --input tmp/imagegen/speed_cat_chroma.png \
  --out assets/branding/speed_cat_mark.png \
  --auto-key border \
  --soft-matte \
  --transparent-threshold 12 \
  --opaque-threshold 220 \
  --despill
```

Inspect the result at full size and at 64 px. If a fringe remains, rerun once
with `--edge-contract 1`; do not change the selected composition during edge
cleanup.

- [ ] **Step 4: Add the deterministic Pillow exporter**

Create `scripts/branding/build_icon_set.py` with these fixed tables and
composition rules:

```python
#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
MARK_PATH = ROOT / "assets/branding/speed_cat_mark.png"
INDIGO_A = (118, 103, 255, 255)
INDIGO_B = (49, 85, 216, 255)
RESAMPLE = Image.Resampling.LANCZOS

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

def gradient(size: int) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    px = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * max(size - 1, 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(INDIGO_A, INDIGO_B))
    return image

def fitted_mark(mark: Image.Image, canvas_size: int, ratio: float = 0.72) -> Image.Image:
    side = round(canvas_size * ratio)
    resized = mark.resize((side, side), RESAMPLE)
    layer = Image.new("RGBA", (canvas_size, canvas_size))
    layer.alpha_composite(resized, ((canvas_size - side) // 2, (canvas_size - side) // 2))
    return layer

def square_icon(mark: Image.Image, size: int) -> Image.Image:
    image = gradient(size)
    image.alpha_composite(fitted_mark(mark, size))
    return image.convert("RGB")

def mac_icon(mark: Image.Image, size: int) -> Image.Image:
    scale = 4
    work = size * scale
    canvas = Image.new("RGBA", (work, work))
    tile_side = round(work * 0.84)
    tile_xy = (work - tile_side) // 2
    mask = Image.new("L", (work, work))
    ImageDraw.Draw(mask).rounded_rectangle(
        (tile_xy, tile_xy, tile_xy + tile_side, tile_xy + tile_side),
        radius=round(tile_side * 0.24),
        fill=255,
    )
    tile = gradient(work)
    tile.putalpha(mask)
    canvas.alpha_composite(tile)
    canvas.alpha_composite(fitted_mark(mark, work, ratio=0.62))
    return canvas.resize((size, size), RESAMPLE)

def save_png(image: Image.Image, relative: str) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)

mark = Image.open(MARK_PATH).convert("RGBA")
save_png(mark, "assets/images/brand_mark.png")
save_png(mac_icon(mark, 1024), "assets/images/brand_logo.png")
save_png(mac_icon(mark, 128), "assets/images/tray_icon.png")

template_source = mark.resize((128, 128), RESAMPLE)
white = (255, 255, 255)
yellow = (255, 215, 94)
trail = (198, 205, 255)

def color_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))

alpha = Image.new("L", (128, 128))
source_pixels = template_source.load()
alpha_pixels = alpha.load()
for y in range(128):
    for x in range(128):
        red, green, blue, source_alpha = source_pixels[x, y]
        if source_alpha < 32:
            continue
        rgb = (red, green, blue)
        nearest = min(
            (white, yellow, trail),
            key=lambda target: color_distance(rgb, target),
        )
        # Keep the cat, turn the bolt into a hole, and omit speed trails.
        if nearest == white:
            alpha_pixels[x, y] = source_alpha

template = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
template.putalpha(alpha)
save_png(template, "assets/images/tray_icon_macos.png")

for size in MAC_SIZES:
    save_png(mac_icon(mark, size), f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png")
for filename, size in IOS.items():
    save_png(square_icon(mark, size), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}")
for density, size in ANDROID.items():
    save_png(square_icon(mark, size), f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")

ico_base = square_icon(mark, 1024)
ico_base.save(
    ROOT / "windows/runner/resources/app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
```

The template classifier intentionally keeps the white cat pixels, turns the
yellow bolt into a knockout, and removes pale-indigo speed-trail pixels.

- [ ] **Step 5: Generate and validate every raster asset**

Run:

```bash
python3 scripts/branding/build_icon_set.py
python3 scripts/branding/validate_brand_assets.py
```

Expected: `validated 32 raster assets and Windows ICO`.

- [ ] **Step 6: Inspect the master and small sizes**

Open:

```bash
open assets/images/brand_logo.png
open macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png
open assets/images/tray_icon_macos.png
```

Expected: the tile, cat, and bolt remain distinct; 32 px has no green fringe;
the template is a single readable alpha silhouette.

- [ ] **Step 7: Commit the generated asset family**

```bash
git add assets/branding assets/images scripts/branding \
  macos/Runner/Assets.xcassets/AppIcon.appiconset \
  ios/Runner/Assets.xcassets/AppIcon.appiconset \
  android/app/src/main/res/mipmap-* \
  windows/runner/resources/app_icon.ico
git commit -m "feat: add Speed Cat brand assets"
```

---

### Task 2: Replace in-app paw placeholders with a shared BrandMark

**Files:**
- Create: `lib/shared/components/brand_mark.dart`
- Create: `test/shared/components/brand_mark_test.dart`
- Modify: `lib/features/onboarding/widget/onboarding_page.dart:183-208`
- Modify: `lib/features/about/widget/about_page.dart:85-107`
- Modify: `lib/features/home/widget/home_page.dart:1295-1325`
- Modify: `test/features/onboarding/widget/onboarding_page_test.dart`
- Modify: `test/features/about/widget/about_page_test.dart`
- Modify: `test/features/home/widget/home_page_test.dart`

**Interfaces:**
- Produces: `enum BrandMarkVariant { tile, transparent }`.
- Produces: `const BrandMark({required double size, BrandMarkVariant variant = BrandMarkVariant.tile, Key? key})`.
- Consumes: `assets/images/brand_logo.png` and `assets/images/brand_mark.png` from Task 1.

- [ ] **Step 1: Add failing page-level expectations**

In the three existing page test files, add assertions after the relevant page
has settled:

```dart
expect(find.byType(BrandMark), findsOneWidget);
expect(
  find.byIcon(FluentIcons.animal_paw_print_20_filled),
  findsNothing,
);
```

For the empty-profile test, also inspect the widget:

```dart
final brand = tester.widget<BrandMark>(find.byType(BrandMark));
expect(brand.variant, BrandMarkVariant.transparent);
```

Create `test/shared/components/brand_mark_test.dart` with:

```dart
import 'package:clashmiao/shared/components/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('maps both variants to the canonical brand assets', (
    tester,
  ) async {
    Future<String> assetFor(BrandMarkVariant variant) async {
      await tester.pumpWidget(
        MaterialApp(home: BrandMark(size: 96, variant: variant)),
      );
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as AssetImage).assetName;
    }

    expect(
      await assetFor(BrandMarkVariant.tile),
      'assets/images/brand_logo.png',
    );
    expect(
      await assetFor(BrandMarkVariant.transparent),
      'assets/images/brand_mark.png',
    );
  });
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
flutter test \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart
```

Expected: compilation failure because `BrandMark` and `BrandMarkVariant` do
not exist.

- [ ] **Step 3: Implement the shared component**

Create `lib/shared/components/brand_mark.dart`:

```dart
import 'package:flutter/material.dart';

enum BrandMarkVariant { tile, transparent }

class BrandMark extends StatelessWidget {
  const BrandMark({
    required this.size,
    this.variant = BrandMarkVariant.tile,
    super.key,
  });

  final double size;
  final BrandMarkVariant variant;

  String get _asset => switch (variant) {
    BrandMarkVariant.tile => 'assets/images/brand_logo.png',
    BrandMarkVariant.transparent => 'assets/images/brand_mark.png',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ClashMiao',
      image: true,
      child: Image.asset(
        _asset,
        key: ValueKey('brand-mark-${variant.name}'),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
```

- [ ] **Step 4: Replace the three paw instances**

Import `brand_mark.dart` in each page and apply:

```dart
// Onboarding hero: keep the 224×224 outer box and 24 px padding.
const BrandMark(size: 176),

// About card: replace the 112×112 decorated paw container.
const BrandMark(size: 112),

// Empty profiles: preserve the existing radial-gradient Stack.
const BrandMark(
  size: 120,
  variant: BrandMarkVariant.transparent,
),
```

Remove only the paw-specific `Container`/`Icon` styling; do not change the
surrounding gaps, scroll behavior, or copy.

- [ ] **Step 5: Run focused tests**

Run:

```bash
flutter test \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Commit the in-app brand integration**

```bash
git add lib/shared/components/brand_mark.dart \
  lib/features/onboarding/widget/onboarding_page.dart \
  lib/features/about/widget/about_page.dart \
  lib/features/home/widget/home_page.dart \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart
git commit -m "feat: use Speed Cat mark in branded surfaces"
```

---

### Task 3: Add Android adaptive and notification variants

**Files:**
- Create: `android/app/src/main/res/drawable/ic_launcher_background.xml`
- Create: `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- Create: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Modify: `android/app/src/main/res/drawable/ic_stat_logo.xml`
- Create: `test/branding/android_icon_resources_test.dart`

**Interfaces:**
- Consumes: the same geometric cat-head, lightning, and indigo palette as the master.
- Produces: Android 8+ adaptive launcher resources while retaining legacy PNGs for older devices.

- [ ] **Step 1: Add a failing resource-contract test**

Create `test/branding/android_icon_resources_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adaptive launcher and Speed Cat notification resources exist', () {
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));

    final notification = File(
      'android/app/src/main/res/drawable/ic_stat_logo.xml',
    ).readAsStringSync();
    expect(notification, contains('android:viewportWidth="24"'));
    expect(notification, isNot(contains('M12,1L3,5v6')));
  });
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
```

Expected: failure because `mipmap-anydpi-v26/ic_launcher.xml` is missing.

- [ ] **Step 3: Add adaptive-icon XML**

Create `mipmap-anydpi-v26/ic_launcher.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
```

Create `drawable/ic_launcher_background.xml` with the approved diagonal
gradient:

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="315"
        android:startColor="#7667FF"
        android:endColor="#3155D8" />
</shape>
```

Create `drawable/ic_launcher_foreground.xml` with the exact 108×108 safe-zone
geometry:

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M27.2,43.1 L39.35,24.2 L48.8,40.4 Q55.55,36.35 62.3,40.4 L74.45,24.2 L82.55,47.15 Q89.3,59.3 82.55,71.45 Q73.1,83.6 54.2,83.6 Q35.3,83.6 25.85,71.45 Q19.1,57.95 27.2,43.1 Z" />
    <path
        android:fillColor="#FFFFD75E"
        android:pathData="M51.5,45.8 L69.05,45.8 L59.6,55.25 L70.4,55.25 L47.45,75.5 L54.2,60.65 L42.05,60.65 Z" />
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#FFC6CDFF"
        android:strokeWidth="4"
        android:strokeLineCap="round"
        android:pathData="M24,51 C17,51 16,45 22,42 M25,64 C17,67 16,60 22,57" />
</vector>
```

- [ ] **Step 4: Replace the notification shield with the monochrome Speed Cat**

Keep the existing 24×24 vector contract and use this even-odd path so the bolt
is a transparent knockout:

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="M4.5,9.75 L7.875,4.5 L10.5,9 Q12.375,7.875 14.25,9 L17.625,4.5 L19.875,10.875 Q21.75,14.25 19.875,17.625 Q17.25,21 12,21 Q6.75,21 4.125,17.625 Q2.25,13.875 4.5,9.75 Z M11.25,10.5 L16.125,10.5 L13.5,13.125 L16.5,13.125 L10.125,18.75 L12,14.625 L8.625,14.625 Z" />
</vector>
```

- [ ] **Step 5: Run resource and Android compile checks**

Run:

```bash
flutter test test/branding/android_icon_resources_test.dart
flutter build apk --debug
```

Expected: test passes and Gradle accepts all vector/adaptive resources. If the
local Android SDK is still unavailable, the test must pass and the APK command
must be recorded as environment-blocked rather than treated as an asset
failure.

- [ ] **Step 6: Commit Android resource integration**

```bash
git add android/app/src/main/res test/branding/android_icon_resources_test.dart
git commit -m "feat: add adaptive Speed Cat Android icons"
```

---

### Task 4: Make tray icons platform-correct

**Files:**
- Modify: `lib/app/tray/tray_controller.dart:140-160, 308-350`
- Modify: `test/app/tray/tray_controller_test.dart`

**Interfaces:**
- Produces: `TrayIconSpec trayIconSpec({required bool isMacOS})`.
- `TrayIconSpec` fields: `String path`, `bool isTemplate`.
- Consumes: `tray_icon_macos.png` and `tray_icon.png` from Task 1.

- [ ] **Step 1: Add failing pure-function and forwarding tests**

Add:

```dart
test('macOS uses the alpha template tray asset', () {
  final spec = trayIconSpec(isMacOS: true);
  expect(spec.path, 'assets/images/tray_icon_macos.png');
  expect(spec.isTemplate, isTrue);
});

test('Windows and Linux use the full-color tray asset', () {
  final spec = trayIconSpec(isMacOS: false);
  expect(spec.path, 'assets/images/tray_icon.png');
  expect(spec.isTemplate, isFalse);
});

test('setTrayIconWithLogging forwards template mode', () async {
  bool? receivedTemplate;
  await setTrayIconWithLogging(
    (path, {isTemplate = false}) async {
      receivedTemplate = isTemplate;
    },
    'assets/images/tray_icon_macos.png',
    isTemplate: true,
  );
  expect(receivedTemplate, isTrue);
});
```

- [ ] **Step 2: Run tray tests and verify failure**

Run:

```bash
flutter test test/app/tray/tray_controller_test.dart
```

Expected: compilation failure because `TrayIconSpec` and `trayIconSpec` do not
exist and `setTrayIconWithLogging` has no `isTemplate` parameter.

- [ ] **Step 3: Implement the platform icon specification**

Add:

```dart
@immutable
class TrayIconSpec {
  const TrayIconSpec({required this.path, required this.isTemplate});

  final String path;
  final bool isTemplate;
}

TrayIconSpec trayIconSpec({required bool isMacOS}) => isMacOS
    ? const TrayIconSpec(
        path: 'assets/images/tray_icon_macos.png',
        isTemplate: true,
      )
    : const TrayIconSpec(
        path: 'assets/images/tray_icon.png',
        isTemplate: false,
      );
```

Change the helper signature to:

```dart
Future<void> setTrayIconWithLogging(
  Future<void> Function(String path, {bool isTemplate}) setIcon,
  String path, {
  bool isTemplate = false,
}) async {
  try {
    await setIcon(path, isTemplate: isTemplate);
  } catch (e) {
    if (kDebugMode) debugPrint('[Tray] setIcon failed: $e');
  }
}
```

In `setup` and status updates, resolve
`trayIconSpec(isMacOS: Platform.isMacOS)` and forward both fields to
`trayManager.setIcon`.

- [ ] **Step 4: Run tray tests**

Run:

```bash
flutter test test/app/tray/tray_controller_test.dart
```

Expected: all tests pass, including existing logging and menu behavior tests.

- [ ] **Step 5: Commit tray behavior**

```bash
git add lib/app/tray/tray_controller.dart test/app/tray/tray_controller_test.dart
git commit -m "fix: render platform-correct tray branding"
```

---

### Task 5: Full verification and running-app review

**Files:**
- Modify only if verification exposes a scoped logo defect.

**Interfaces:**
- Consumes every output from Tasks 1–4.
- Produces the final proof that launcher, in-app, tray, and notification assets are coherent and buildable.

- [ ] **Step 1: Run formatting and focused tests**

Run:

```bash
dart format lib/shared/components/brand_mark.dart \
  lib/features/onboarding/widget/onboarding_page.dart \
  lib/features/about/widget/about_page.dart \
  lib/features/home/widget/home_page.dart \
  lib/app/tray/tray_controller.dart \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart \
  test/app/tray/tray_controller_test.dart \
  test/branding/android_icon_resources_test.dart

flutter test \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart \
  test/app/tray/tray_controller_test.dart \
  test/branding/android_icon_resources_test.dart
```

Expected: formatter exits 0 and all focused tests pass.

- [ ] **Step 2: Run asset validation and static analysis**

Run:

```bash
python3 scripts/branding/validate_brand_assets.py
flutter analyze
```

Expected: asset validation passes and analysis reports no new errors.

- [ ] **Step 3: Build and launch macOS**

Run:

```bash
flutter build macos --debug --no-tree-shake-icons
open build/macos/Build/Products/Debug/clashmiao.app
```

Expected: build exits 0 and the application remains running.

- [ ] **Step 4: Inspect the exact onboarding surface reported by the user**

Reset the local onboarding preference only in the test/development app data,
relaunch, and inspect with Computer Use. Confirm:

- the large paw circle from the supplied screenshot is gone;
- the full-color Speed Cat tile appears in the same hero area;
- the cards and “开始” button retain their existing layout;
- the Dock icon shows the matching Speed Cat tile.

- [ ] **Step 5: Inspect small/system representations**

Confirm the built app contains:

```bash
ls -lh build/macos/Build/Products/Debug/clashmiao.app/Contents/Frameworks/libcore.dylib
file windows/runner/resources/app_icon.ico
python3 scripts/branding/validate_brand_assets.py
```

Inspect the menu-bar icon in both light and dark appearances. It must be tinted
by AppKit and preserve the cat/bolt silhouette.

- [ ] **Step 6: Review changes and commit any final scoped corrections**

Run:

```bash
git diff --check
git status --short
```

If verification required a logo-scoped correction, stage only the branding,
brand-widget, platform-icon, and related test paths and commit:

```bash
git add assets/branding assets/images scripts/branding \
  lib/shared/components/brand_mark.dart \
  lib/features/onboarding/widget/onboarding_page.dart \
  lib/features/about/widget/about_page.dart \
  lib/features/home/widget/home_page.dart \
  lib/app/tray/tray_controller.dart \
  macos/Runner/Assets.xcassets/AppIcon.appiconset \
  ios/Runner/Assets.xcassets/AppIcon.appiconset \
  android/app/src/main/res windows/runner/resources/app_icon.ico \
  test/shared/components/brand_mark_test.dart \
  test/features/onboarding/widget/onboarding_page_test.dart \
  test/features/about/widget/about_page_test.dart \
  test/features/home/widget/home_page_test.dart \
  test/app/tray/tray_controller_test.dart \
  test/branding/android_icon_resources_test.dart
git commit -m "fix: polish Speed Cat brand rendering"
```

Do not commit build products, generated Flutter ephemeral files, or unrelated
local changes.
