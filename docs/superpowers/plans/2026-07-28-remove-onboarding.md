# Remove Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the onboarding screen and make every application launch open the existing main `ShellPage` immediately.

**Architecture:** Replace the asynchronous root gate with a direct `ShellPage` route. Then remove the now-unreachable onboarding page, completion provider, onboarding-only region detector, their tests, and the detector's dedicated dependency. Existing preferences and main-page state remain untouched.

**Tech Stack:** Flutter, Dart, GoRouter, Riverpod, SharedPreferences, Flutter widget tests, macOS Debug build.

## Global Constraints

- `/` renders `ShellPage` without reading `onboarding_done`.
- No `/onboarding` route, loading gate, or onboarding error fallback remains.
- Analytics remains opt-in with default `false`.
- Locale continues to use a saved choice or the device locale.
- Network region retains the existing `other` default and remains editable in configuration.
- Existing main navigation, profiles, settings, deep links, and saved preferences remain unchanged.

---

### Task 1: Route every startup directly to `ShellPage`

**Files:**
- Create: `test/app/router/app_router_test.dart`
- Modify: `lib/app/router/app_router.dart`

**Interfaces:**
- Consumes: global `appRouter` and existing `ShellPage`.
- Produces: root route `/` whose builder returns `const ShellPage()`.

- [ ] **Step 1: Add a failing cold-start router widget test**

Create `test/app/router/app_router_test.dart` with empty onboarding
preferences and the same real ShellPage dependencies used by
`test/app/shell_page_test.dart`:

```dart
import 'package:clashmiao/app/router/app_router.dart';
import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  testWidgets('空偏好冷启动直接进入主页面', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    PackageInfo.setMockInitialValues(
      appName: 'ClashMiao',
      packageName: 'com.clashmiao.app',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileListProvider.overrideWith((_) => Future.value(const [])),
        activeProfileProvider.overrideWith((_) => Future.value(null)),
        offlineProxyGroupsProvider.overrideWith((_) => Future.value(const [])),
        outboundGroupsProvider.overrideWith(
          (_) => Stream<List<OutboundGroup>>.value(const []),
        ),
        boxStatsProvider.overrideWith((_) => Stream.value(BoxStats.empty)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp.router(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            routerConfig: appRouter,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_0')), findsOneWidget);
    expect(prefs.containsKey('onboarding_done'), isFalse);
  });
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
flutter test test/app/router/app_router_test.dart
```

Expected: failure because empty preferences currently render
`OnboardingPage`, not `ShellPage`.

- [ ] **Step 3: Replace the root gate with the direct route**

Reduce `app_router.dart` to:

```dart
import 'package:clashmiao/app/shell_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRouterNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: appRouterNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ShellPage()),
  ],
);
```

- [ ] **Step 4: Verify the router test GREEN**

Run:

```bash
flutter test test/app/router/app_router_test.dart
```

Expected: the test passes, ShellPage is present, and no completion flag is
written.

- [ ] **Step 5: Commit direct startup**

```bash
git add lib/app/router/app_router.dart test/app/router/app_router_test.dart
git commit -m "feat: open ClashMiao directly on main page"
```

### Task 2: Delete onboarding-only code

**Files:**
- Delete: `lib/features/onboarding/widget/onboarding_page.dart`
- Delete: `lib/core/onboarding/onboarding_state.dart`
- Delete: `lib/core/region/region_detection_service.dart`
- Delete: `test/features/onboarding/widget/onboarding_page_test.dart`
- Delete: `test/core/region/region_detection_service_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: onboarding-specific comments in `lib/main.dart`, `lib/core/providers/app_providers.dart`, `lib/shared/components/analytics_toggle_tile.dart`, `lib/features/settings/widget/settings_page.dart`, `lib/app/tray/tray_controller.dart`, and `lib/core/config/build_config.dart`

**Interfaces:**
- Consumes: the direct root route from Task 1.
- Produces: no compiled onboarding page, state provider, or region detector.

- [ ] **Step 1: Delete the unused feature files and tests**

Delete the five exact files listed above. Do not delete shared
`BrandMark`, `AnalyticsToggleTile`, locale preferences, network settings, or
terms configuration.

- [ ] **Step 2: Remove the dedicated dependency**

Delete these lines from `pubspec.yaml`:

```yaml
  # 地区识别（首次启动时区/IP 兜底推断国家码，onboarding 自动选地区/语言）
  timezone_to_country: ^3.2.0
```

Run:

```bash
flutter pub get
```

Expected: `pubspec.lock` no longer contains `timezone_to_country`.

- [ ] **Step 3: Remove stale onboarding references from comments**

Update comments without changing runtime code:

- main/settings analytics comments describe the settings preference only;
- shared analytics component comments describe current settings usage;
- tray route comments state that `/` is the only GoRouter page route;
- terms URL comments no longer claim an onboarding row displays it.

- [ ] **Step 4: Prove deleted symbols are gone**

Run:

```bash
rg -n \
  "OnboardingPage|onboardingDoneProvider|markOnboardingDone|/onboarding|regionDetectionServiceProvider|timezone_to_country" \
  lib test pubspec.yaml pubspec.lock
```

Expected: no matches.

- [ ] **Step 5: Run focused regression checks**

Run:

```bash
flutter analyze
flutter test test/app/router/app_router_test.dart test/app/shell_page_test.dart
```

Expected: no analysis issues and all router/ShellPage tests pass.

- [ ] **Step 6: Commit removal**

```bash
git add -u
git add pubspec.lock
git commit -m "refactor: remove onboarding feature"
```

### Task 3: Verify, rebuild, and inspect direct startup

**Files:**
- Verify only: repository tests and generated Debug bundle.

**Interfaces:**
- Consumes: committed direct-start router and removed onboarding feature.
- Produces: a signed macOS Debug app that opens directly on the main home page.

- [ ] **Step 1: Run complete verification**

```bash
flutter analyze
bash bin/test-unit.sh
git diff --check
```

Expected: analysis has no issues, the complete remaining test suite passes with
no failures, and diff check is empty.

- [ ] **Step 2: Build and verify the macOS bundle**

```bash
flutter build macos --debug --no-tree-shake-icons
codesign --verify --deep --strict \
  build/macos/Build/Products/Debug/clashmiao.app
```

Expected: both commands exit 0.

- [ ] **Step 3: Replace the running application**

Resolve the exact current ClashMiao PID, terminate it normally, launch the
worktree Debug bundle, and confirm it is the only ClashMiao executable.

- [ ] **Step 4: Inspect the real cold-start window**

Use Computer Use to capture the actual application. Confirm:

- the first visible page is the main home page;
- the onboarding logo, language, region, analytics cards, and Start button do
  not appear;
- bottom navigation is visible;
- the process path points to this worktree's Debug bundle.

- [ ] **Step 5: Commit any required correction**

If inspection reveals a defect, add a focused failing test before correcting
it, then commit:

```bash
git add -u
git commit -m "fix: polish direct main-page startup"
```

If no correction is required, do not create an empty commit.
