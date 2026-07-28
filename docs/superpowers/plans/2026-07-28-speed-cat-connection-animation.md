# Speed Cat Connection Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every active-profile VPN power button icon with the layered Speed Cat mark and animate its lightning and blue halo from the real connection status.

**Architecture:** Generate separate transparent cat and bolt assets from the existing canonical mark so the two shapes cannot drift from the brand. A focused `SpeedCatConnectionMark` stateful widget owns the 600ms activation timeline and connected pulse, while `ConnectionButton` keeps all existing tap gating, VPN state handling, and status copy.

**Tech Stack:** Flutter/Dart, Riverpod, Flutter animation controllers, Pillow brand asset generator, Flutter widget tests, Python `unittest`.

## Global Constraints

- Preserve all unrelated uncommitted theme and layout changes already present in the worktree.
- The VPN controller and `ConnectionButton.onTap` data flow must not change.
- The cat remains horizontally centered and the existing tailless brand geometry remains unchanged.
- Activation lasts about 600ms: bolt rises about 8px, scales to about 1.18, brightens, then settles.
- Blue/indigo are the only halo colors; normal disconnect must not use an error-red flash.
- `BoxStatus` is the only source of truth; no delayed fake success state.
- Respect `MediaQuery.disableAnimations`.
- Do not add a new runtime dependency.

---

### Task 1: Generate Separate Cat and Lightning Assets

**Files:**
- Modify: `scripts/branding/test_build_icon_set.py`
- Modify: `scripts/branding/build_icon_set.py`
- Modify: `scripts/branding/validate_brand_assets.py`
- Modify: `scripts/branding/test_validate_brand_assets.py`
- Create: `assets/images/brand_cat.png`
- Create: `assets/images/brand_bolt.png`

**Interfaces:**
- Consumes: canonical `assets/branding/speed_cat_mark_source.png`, `build_refined_mark()`, `color_class_mask()`, `WHITE`, and `YELLOW`.
- Produces: `build_brand_layer(mark: Image.Image, color: tuple[int, int, int]) -> Image.Image` plus two 1024×1024 transparent RGBA image assets.

- [ ] **Step 1: Write the failing layer-generation tests**

Add tests that assert the requested layer contains exactly the corresponding color mask and has transparent corners:

```python
def test_brand_layers_split_cat_and_bolt_without_moving_them(self) -> None:
    cat = build_icon_set.build_brand_layer(
        self.refined,
        build_icon_set.WHITE,
    )
    bolt = build_icon_set.build_brand_layer(
        self.refined,
        build_icon_set.YELLOW,
    )

    self.assertEqual(cat.mode, "RGBA")
    self.assertEqual(bolt.mode, "RGBA")
    self.assertEqual(cat.getpixel((0, 0))[3], 0)
    self.assertEqual(bolt.getpixel((0, 0))[3], 0)
    self.assertEqual(
        cat.getchannel("A").getbbox(),
        build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.WHITE,
        ).getbbox(),
    )
    self.assertEqual(
        bolt.getchannel("A").getbbox(),
        build_icon_set.color_class_mask(
            self.refined,
            build_icon_set.YELLOW,
        ).getbbox(),
    )
```

Extend validation tests so a missing, opaque-corner, or incorrectly colored layer is rejected.

- [ ] **Step 2: Run the Python tests and verify RED**

Run:

```bash
cd scripts/branding
python3 -m unittest test_build_icon_set.py test_validate_brand_assets.py
```

Expected: FAIL because `build_brand_layer` and the two expected output files do not exist.

- [ ] **Step 3: Implement the layer generator**

Add the exact layer helper:

```python
def build_brand_layer(
    mark: Image.Image,
    color: tuple[int, int, int],
) -> Image.Image:
    mask = color_class_mask(mark, color)
    layer = Image.new("RGBA", mark.size, (*color, 255))
    layer.putalpha(mask)
    return layer
```

In `main()`, derive both assets from the refined tailless `mark`:

```python
save_png(
    build_brand_layer(mark, WHITE),
    "assets/images/brand_cat.png",
)
save_png(
    build_brand_layer(mark, YELLOW),
    "assets/images/brand_bolt.png",
)
```

Add both paths to `validate_brand_assets.EXPECTED` and validate transparent corners and color-class geometry.

- [ ] **Step 4: Generate assets and verify GREEN**

Run:

```bash
python3 scripts/branding/build_icon_set.py
(cd scripts/branding && python3 -m unittest test_build_icon_set.py test_validate_brand_assets.py)
python3 scripts/branding/validate_brand_assets.py
```

Expected: all Python tests pass and validation reports both new raster assets.

- [ ] **Step 5: Commit only the brand-layer deliverable**

```bash
git add scripts/branding/test_build_icon_set.py \
  scripts/branding/build_icon_set.py \
  scripts/branding/validate_brand_assets.py \
  scripts/branding/test_validate_brand_assets.py \
  assets/images/brand_cat.png \
  assets/images/brand_bolt.png
git commit -m "feat: add layered Speed Cat assets"
```

---

### Task 2: Build the Status-Driven Speed Cat Motion Component

**Files:**
- Create: `lib/features/home/widget/speed_cat_connection_mark.dart`
- Create: `test/features/home/widget/speed_cat_connection_mark_test.dart`

**Interfaces:**
- Consumes: `BoxStatus`, `BrandColors.indigo`, `BrandColors.indigoDeep`, `assets/images/brand_cat.png`, and `assets/images/brand_bolt.png`.
- Produces:

```dart
class SpeedCatConnectionMark extends StatefulWidget {
  const SpeedCatConnectionMark({
    required this.status,
    this.size = 112,
    super.key,
  });

  final BoxStatus status;
  final double size;
}
```

Stable test keys:

```dart
const ValueKey('connection-speed-cat');
const ValueKey('connection-cat-layer');
const ValueKey('connection-bolt-transform');
const ValueKey('connection-bolt-layer');
const ValueKey('connection-blue-halo');
const ValueKey('connection-ripple-0');
const ValueKey('connection-ripple-1');
```

- [ ] **Step 1: Write failing widget tests for identity and status**

Create a minimal Material host and assert:

```dart
testWidgets('四种连接状态都使用分层猫咪 Logo', (tester) async {
  for (final status in <BoxStatus>[
    const BoxStopped(),
    const BoxStarting(),
    const BoxStarted(),
    const BoxStopping(),
  ]) {
    await tester.pumpWidget(_host(status));
    expect(find.byKey(const ValueKey('connection-cat-layer')), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-bolt-layer')), findsOneWidget);
  }
});

testWidgets('连接中闪电独立上抬放大并出现蓝色光圈', (tester) async {
  await tester.pumpWidget(_host(const BoxStarting()));
  await tester.pump(const Duration(milliseconds: 220));

  final transform = tester.widget<Transform>(
    find.byKey(const ValueKey('connection-bolt-transform')),
  );
  expect(transform.transform.getTranslation().y, lessThan(-6));
  expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1.15));
  expect(find.byKey(const ValueKey('connection-ripple-0')), findsOneWidget);
  expect(find.byKey(const ValueKey('connection-ripple-1')), findsOneWidget);
});

testWidgets('已连接保留蓝色呼吸光', (tester) async {
  await tester.pumpWidget(_host(const BoxStarted()));
  expect(find.byKey(const ValueKey('connection-blue-halo')), findsOneWidget);
});
```

Add a reduced-motion host with `MediaQueryData(disableAnimations: true)` and assert the component renders the correct layers without a transient raised transform.

- [ ] **Step 2: Run the component tests and verify RED**

Run:

```bash
flutter test test/features/home/widget/speed_cat_connection_mark_test.dart
```

Expected: FAIL because `SpeedCatConnectionMark` does not exist.

- [ ] **Step 3: Implement the minimal animation component**

Use one 600ms activation controller and one 2400ms connected pulse controller. Start or stop them only from `initState`, `didUpdateWidget`, and `didChangeDependencies`.

The activation timeline must be encoded as tween sequences:

```dart
final boltLift = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(begin: 0, end: -8)
        .chain(CurveTween(curve: Curves.easeOutCubic)),
    weight: 37,
  ),
  TweenSequenceItem(
    tween: Tween(begin: -8, end: -2)
        .chain(CurveTween(curve: Curves.easeOutBack)),
    weight: 63,
  ),
]);

final boltScale = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(begin: 1, end: 1.18)
        .chain(CurveTween(curve: Curves.easeOutBack)),
    weight: 37,
  ),
  TweenSequenceItem(
    tween: Tween(begin: 1.18, end: 1.04)
        .chain(CurveTween(curve: Curves.easeOutCubic)),
    weight: 63,
  ),
]);
```

Build the transform as one matrix so tests can inspect both properties:

```dart
Transform(
  key: const ValueKey('connection-bolt-transform'),
  alignment: Alignment.center,
  transform: Matrix4.identity()
    ..translate(0.0, boltLift.value)
    ..scale(boltScale.value),
  child: Image.asset(
    'assets/images/brand_bolt.png',
    key: const ValueKey('connection-bolt-layer'),
  ),
)
```

Draw activation ripples with scale-and-opacity values from the activation controller. When connected, drive a low-opacity halo and intermittent ring from the pulse controller. Wrap the mark in `RepaintBoundary`. When `MediaQuery.disableAnimations` is true, stop both controllers and render the settled static frame.

- [ ] **Step 4: Run focused component tests and verify GREEN**

Run:

```bash
dart format lib/features/home/widget/speed_cat_connection_mark.dart \
  test/features/home/widget/speed_cat_connection_mark_test.dart
flutter test test/features/home/widget/speed_cat_connection_mark_test.dart
```

Expected: all component tests pass with no pending timer warning.

- [ ] **Step 5: Commit the isolated motion component**

```bash
git add lib/features/home/widget/speed_cat_connection_mark.dart \
  test/features/home/widget/speed_cat_connection_mark_test.dart
git commit -m "feat: animate the Speed Cat connection mark"
```

---

### Task 3: Replace the Generic VPN Icon Without Changing VPN Logic

**Files:**
- Modify: `lib/features/home/widget/connection_button.dart`
- Modify: `test/features/home/widget/connection_button_test.dart`

**Interfaces:**
- Consumes: `SpeedCatConnectionMark(status: status, size: 112)`.
- Produces: the unchanged public `ConnectionButton({required BoxStatus status, required VoidCallback onTap})`.

- [ ] **Step 1: Write failing integration tests**

Extend `connection_button_test.dart`:

```dart
testWidgets('所有状态的连接按钮都显示猫咪 Logo，不显示通用状态图标', (
  tester,
) async {
  for (final status in <BoxStatus>[
    const BoxStopped(),
    const BoxStarting(),
    const BoxStarted(),
    const BoxStopping(),
  ]) {
    await tester.pumpWidget(await _host(status));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(SpeedCatConnectionMark), findsOneWidget);
    expect(find.byIcon(FluentIcons.power_24_regular), findsNothing);
    expect(find.byIcon(FluentIcons.arrow_sync_24_regular), findsNothing);
    expect(find.byIcon(FluentIcons.shield_checkmark_24_regular), findsNothing);
  }
});

testWidgets('切换期间猫咪按钮禁止重复点击', (tester) async {
  var taps = 0;
  await tester.pumpWidget(
    await _host(const BoxStarting(), onTap: () => taps++),
  );
  await tester.tap(find.byType(ConnectionButton));
  expect(taps, 0);
});
```

- [ ] **Step 2: Run integration tests and verify RED**

Run:

```bash
flutter test test/features/home/widget/connection_button_test.dart
```

Expected: FAIL because `ConnectionButton` still renders the generic power/sync/shield `Icon`.

- [ ] **Step 3: Integrate the new mark**

Preserve the currently uncommitted `BrandColors` import and other theme work. Remove the generic `IconData` selection and render:

```dart
SpeedCatConnectionMark(
  status: status,
  size: 112,
),
const SizedBox(height: 6),
Text(
  statusText.toUpperCase(),
  // keep the existing typography
),
```

Use the same indigo-to-deep-indigo circular gradient for all four states. Let `SpeedCatConnectionMark` own all ripple rings and remove the old `_RippleRing` implementation from this file. Keep `_handleConnectionTap`, experimental feature confirmation, status text, disabled switching behavior, and `onTap` unchanged.

- [ ] **Step 4: Run the focused home tests and verify GREEN**

Run:

```bash
dart format lib/features/home/widget/connection_button.dart \
  test/features/home/widget/connection_button_test.dart
flutter test \
  test/features/home/widget/speed_cat_connection_mark_test.dart \
  test/features/home/widget/connection_button_test.dart \
  test/features/home/widget/connection_button_experimental_notice_test.dart \
  test/features/home/widget/home_page_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 5: Commit only the connection-button hunks**

Before staging, compare against the pre-existing dirty diff and ensure no unrelated layout/theme file is included:

```bash
git diff -- lib/features/home/widget/connection_button.dart \
  test/features/home/widget/connection_button_test.dart
git add lib/features/home/widget/connection_button.dart \
  test/features/home/widget/connection_button_test.dart
git diff --cached --check
git commit -m "feat: use Speed Cat for VPN connection"
```

---

### Task 4: Verify, Build, Restart, and Inspect

**Files:**
- No production source changes expected.
- Build output: `build/macos/Build/Products/Debug/clashmiao.app`

**Interfaces:**
- Consumes: the completed layered assets and connection widget.
- Produces: a signed, locally running macOS debug app.

- [ ] **Step 1: Verify references, formatting, and static analysis**

Run:

```bash
rg -n "power_24_regular|arrow_sync_24_regular|shield_checkmark_24_regular" \
  lib/features/home/widget/connection_button.dart
dart format --output=none --set-exit-if-changed \
  lib/features/home/widget/speed_cat_connection_mark.dart \
  lib/features/home/widget/connection_button.dart \
  test/features/home/widget/speed_cat_connection_mark_test.dart \
  test/features/home/widget/connection_button_test.dart
flutter analyze
```

Expected: `rg` finds no generic connection icons, formatting is clean, and analysis reports no issues.

- [ ] **Step 2: Run all tests and brand validation**

Run:

```bash
set -o pipefail
bash bin/test-unit.sh
(cd scripts/branding && \
  python3 -m unittest test_build_icon_set.py test_validate_brand_assets.py)
python3 scripts/branding/validate_brand_assets.py
git diff --check
```

Expected: all Flutter and Python tests pass; all raster assets validate.

- [ ] **Step 3: Build and verify the macOS bundle**

Run:

```bash
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: build succeeds and `codesign` exits 0. If CocoaPods changes only its generated version line in `macos/Podfile.lock`, restore that one unrelated line before continuing.

- [ ] **Step 4: Restart the exact debug app**

Resolve the currently running process path, terminate only the exact worktree build, open the rebuilt bundle, and poll until the new process exists:

```bash
ps -axo pid=,command= | \
  rg '/logo-redesign/build/macos/Build/Products/Debug/clashmiao.app/'
open build/macos/Build/Products/Debug/clashmiao.app
```

Expected: exactly one `clashmiao` process runs from this worktree bundle.

- [ ] **Step 5: Inspect the actual active-profile page**

Use the Computer Use skill read-only to raise the window and capture the page. Verify:

- The active-profile connection button shows the Speed Cat mark.
- The power, sync, and shield icons are absent.
- The status text and surrounding layout remain readable.
- No onboarding page returns.

Do not click the real VPN control during automated inspection because that changes the machine's network/VPN state. The animation itself is verified by widget tests; the user can trigger the final real-network interaction.

- [ ] **Step 6: Final branch state**

Run:

```bash
git status --short
git log --oneline --decorate -8
```

Expected: animation commits are present; unrelated pre-existing theme/layout edits remain preserved and unstaged.
