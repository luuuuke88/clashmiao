# Bottom Navigation Solid Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the floating bottom navigation an approved solid blue-gray surface in light and dark modes, then rebuild and relaunch the macOS app.

**Architecture:** Keep `_GlassBottomNav` and its navigation behavior intact. Change only the keyed bar container's theme-dependent background, extend the existing ShellPage widget host so both brightness modes can be tested, and verify the rendered `BoxDecoration` through `bottom_nav_bar`.

**Tech Stack:** Flutter, Dart, Material `ThemeData`, `flutter_test`, macOS Flutter build.

## Global Constraints

- Light-mode background is exactly `Color(0xFFEEF1F7)`.
- Dark-mode background is exactly `Color(0xFF1B1D24)`.
- Keep the existing 68 px height, capsule radius, outer spacing, border, shadow, icon geometry, labels, foreground colors, selected state, and tap behavior.
- Do not add another selected-item capsule or change navigation behavior.
- Preserve and exclude unrelated existing worktree changes; `lib/app/shell_page.dart` and `test/app/shell_page_test.dart` already contain user-owned overlapping edits.
- Add no dependency.

---

### Task 1: Solid bottom-navigation surface

**Files:**
- Modify: `lib/app/shell_page.dart:391-489`
- Modify: `test/app/shell_page_test.dart:20-145`

**Interfaces:**
- Consumes: `ValueKey('bottom_nav_bar')`, the existing `_GlassBottomNav`, and the existing `_host` widget-test helper.
- Produces: a light/dark `BoxDecoration.color` contract for the rendered navigation bar; no new public API.

- [ ] **Step 1: Write the failing light- and dark-mode tests**

Extend `_host` with a brightness parameter:

```dart
Future<(Widget, ProviderContainer)> _host({
  List<Override> extraOverrides = const [],
  Brightness brightness = Brightness.light,
}) async {
  // Keep the existing provider setup.
  final aiUiTheme =
      brightness == Brightness.light ? AiUiTheme.light : AiUiTheme.dark;

  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData(brightness: brightness).copyWith(
            extensions: <ThemeExtension<dynamic>>[aiUiTheme],
          ),
          // Keep the existing MediaQuery builder and ShellPage home.
        ),
      ),
    ),
    container,
  );
}
```

Add focused assertions:

```dart
testWidgets('底部导航在浅色模式使用实色蓝灰白底', (tester) async {
  final (widget, container) = await _host();
  addTearDown(container.dispose);

  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 300));

  final bar = tester.widget<Container>(
    find.byKey(const ValueKey('bottom_nav_bar')),
  );
  final decoration = bar.decoration! as BoxDecoration;
  expect(decoration.color, const Color(0xFFEEF1F7));
});

testWidgets('底部导航在深色模式使用实色深蓝黑底', (tester) async {
  final (widget, container) = await _host(brightness: Brightness.dark);
  addTearDown(container.dispose);

  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 300));

  final bar = tester.widget<Container>(
    find.byKey(const ValueKey('bottom_nav_bar')),
  );
  final decoration = bar.decoration! as BoxDecoration;
  expect(decoration.color, const Color(0xFF1B1D24));
});
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
flutter test test/app/shell_page_test.dart \
  --plain-name '底部导航在浅色模式使用实色蓝灰白底'
flutter test test/app/shell_page_test.dart \
  --plain-name '底部导航在深色模式使用实色深蓝黑底'
```

Expected: both tests fail because the current colors are 50%-alpha white and `#16161A`.

- [ ] **Step 3: Implement the approved surface colors**

In the `BoxDecoration` of the container keyed `bottom_nav_bar`, replace only
the current transparent color expression:

```dart
color: isLight
    ? const Color(0xFFEEF1F7)
    : const Color(0xFF1B1D24),
```

Update the nearby comment so it describes a near-solid foreground surface,
not transparent glass. Leave the existing blur, edge border, capsule geometry,
shadow, icons, labels, colors, and gesture handling unchanged.

- [ ] **Step 4: Run GREEN and regression checks**

Run:

```bash
dart format --output=none --set-exit-if-changed \
  lib/app/shell_page.dart test/app/shell_page_test.dart
flutter test test/app/shell_page_test.dart \
  --plain-name '底部导航在浅色模式使用实色蓝灰白底'
flutter test test/app/shell_page_test.dart \
  --plain-name '底部导航在深色模式使用实色深蓝黑底'
flutter test test/app/shell_page_test.dart \
  --plain-name 'ShellPage 保持 4 项玻璃底部导航'
flutter test test/app/shell_page_test.dart \
  --plain-name 'ShellPage 底部导航是浮起来的胶囊（左右留边、圆角等于半个高度）'
flutter analyze lib/app/shell_page.dart test/app/shell_page_test.dart
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: focused tests pass, analysis reports no issues, macOS build succeeds,
and strict signing verification exits 0.

- [ ] **Step 5: Relaunch and inspect**

Stop only the exact running binary for this worktree, open the newly built
bundle, confirm exactly one matching process remains, and inspect the current
window without clicking the VPN control.

Because both modified source/test files already contain overlapping user-owned
changes, do not stage or commit either whole file unless the implementation
hunks can be isolated without including those existing changes. Report the
source diff and leave unrelated edits intact.
