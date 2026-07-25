import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/settings/widget/per_app_proxy_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个合法的最小 1x1 透明 PNG，用来驱动"图标加载成功"路径——
/// 必须是真实可解码的 PNG 字节，不能随便拼字符串,否则 Image.memory
/// 在 paint 阶段的异步 codec 解码会抛错，污染测试输出。
const _minimalPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';

Future<Widget> _host({String locale = 'zhCn'}) async {
  SharedPreferences.setMockInitialValues({'locale': locale});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PerAppProxyPage()),
  );
}

Future<Widget> _routedHost() async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    'per_app_proxy_mode': 'include',
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PerAppProxyPage(),
                  ),
                );
              },
              child: const Text('Open per-app proxy'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('PerAppProxyPage renders mode header with search toggle', (
    tester,
  ) async {
    await tester.pumpWidget(await _host());
    await tester.pump();

    expect(find.text('分应用线路'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.text('代理所有应用程序'), findsOneWidget);
    expect(find.text('仅代理选定的应用程序'), findsOneWidget);
    expect(find.text('不代理选中的应用程序'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('选择 off 模式后返回上一页', (tester) async {
    await tester.pumpWidget(await _routedHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open per-app proxy'));
    await tester.pumpAndSettle();

    expect(find.text('分应用线路'), findsOneWidget);
    expect(find.text('代理所有应用程序'), findsOneWidget);

    await tester.tap(find.text('代理所有应用程序'));
    await tester.pumpAndSettle();

    expect(find.text('Open per-app proxy'), findsOneWidget);
    expect(find.text('分应用线路'), findsNothing);
  });

  // ===============================================================
  // 加载失败 error state：真实 Pigeon 调用被 Platform.isAndroid 挡在测试
  // 宿主机（非 Android）之外,没法直接从 method channel 层面注入异常。
  // 用 debugAppsLoader（@visibleForTesting 注入点,参照 ProxiesPage 已有的
  // debugOpenProxyNameModal 先例）绕开真实 Pigeon 调用 + Platform 判断，
  // 直接驱动 _loadApps 的成功/失败分支。
  // ===============================================================

  Future<Widget> errorHost(
    Future<List<pigeon.InstalledApp>> Function() loader, {
    String locale = 'zhCn',
  }) async {
    SharedPreferences.setMockInitialValues({'locale': locale});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: PerAppProxyPage(debugAppsLoader: loader)),
    );
  }

  testWidgets('加载中显示 loading 指示器，不显示错误态', (tester) async {
    final completer = Completer<List<pigeon.InstalledApp>>();
    await tester.pumpWidget(await errorHost(() => completer.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('重试'), findsNothing);

    completer.complete(const []);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('加载应用列表失败 → 显示错误态和重试按钮，而不是一直转圈', (tester) async {
    await tester.pumpWidget(
      await errorHost(() async => throw Exception('native failure')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  // ===============================================================
  // 加载失败文案 / 空态文案曾经是硬编码中英文混杂字面量，跟 locale 无关。
  // 这里钉住切到英文 locale 后这两块文案必须走 i18n、不能停在硬编码原文。
  // ===============================================================

  testWidgets('英文 locale 下加载应用列表失败 → 错误态文案走 i18n', (tester) async {
    await tester.pumpWidget(
      await errorHost(
        () async => throw Exception('native failure'),
        locale: 'en',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Failed to load app list'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('加载应用列表失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('英文 locale 下非 Android 空态文案走 i18n', (tester) async {
    await tester.pumpWidget(await _host(locale: 'en'));
    await tester.pump();

    expect(
      find.text('Per-app line mode is only supported on Android'),
      findsOneWidget,
    );
    expect(find.text('仅 Android 支持分应用线路'), findsNothing);
  });

  testWidgets('点击重试按钮 → 重新加载成功后显示应用列表并清除错误态', (tester) async {
    var callCount = 0;
    Future<List<pigeon.InstalledApp>> loader() async {
      callCount++;
      if (callCount == 1) {
        throw Exception('native failure');
      }
      return [
        pigeon.InstalledApp(
          packageName: 'com.example.app',
          appName: 'Example App',
          isSystemApp: false,
        ),
      ];
    }

    await tester.pumpWidget(await errorHost(loader));
    await tester.pump();
    await tester.pump();

    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();

    expect(callCount, 2);
    expect(find.text('重试'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Example App'), findsOneWidget);
  });

  // ===============================================================
  // 应用图标：每行应展示真实图标（通过 getAppIconBase64 拉取），而不是
  // 所有行共用同一个通用图标。用 debugIconLoader（跟 debugAppsLoader 同一
  // 套注入点思路）绕开真实 Pigeon 调用驱动成功 / 失败 / 缓存三条路径。
  // ===============================================================

  Future<Widget> iconHost({
    required List<pigeon.InstalledApp> apps,
    required Future<String?> Function(String packageName) iconLoader,
  }) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: PerAppProxyPage(
          debugAppsLoader: () async => apps,
          debugIconLoader: iconLoader,
        ),
      ),
    );
  }

  testWidgets('图标加载成功 → 该行渲染 Image.memory 而不是通用图标', (tester) async {
    await tester.pumpWidget(
      await iconHost(
        apps: [
          pigeon.InstalledApp(
            packageName: 'com.example.app',
            appName: 'Example App',
            isSystemApp: false,
          ),
        ],
        iconLoader: (_) async => _minimalPngBase64,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final imageFinder = find.byWidgetPredicate((w) => w is Image);
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(image.image, isA<MemoryImage>());
    expect((image.image as MemoryImage).bytes, base64Decode(_minimalPngBase64));
    expect(find.byIcon(FluentIcons.apps_24_regular), findsNothing);
  });

  testWidgets('图标加载返回 null → 优雅降级为通用图标，不崩溃', (tester) async {
    await tester.pumpWidget(
      await iconHost(
        apps: [
          pigeon.InstalledApp(
            packageName: 'com.example.app',
            appName: 'Example App',
            isSystemApp: false,
          ),
        ],
        iconLoader: (_) async => null,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(FluentIcons.apps_24_regular), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image), findsNothing);
  });

  testWidgets('图标加载抛异常 → 优雅降级为通用图标，不崩溃', (tester) async {
    await tester.pumpWidget(
      await iconHost(
        apps: [
          pigeon.InstalledApp(
            packageName: 'com.example.app',
            appName: 'Example App',
            isSystemApp: false,
          ),
        ],
        iconLoader: (_) async => throw Exception('native icon failure'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(FluentIcons.apps_24_regular), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Image), findsNothing);
  });

  testWidgets('同一包名的图标只请求一次（内存缓存生效）', (tester) async {
    var callCount = 0;
    Future<String?> iconLoader(String packageName) async {
      callCount++;
      return _minimalPngBase64;
    }

    await tester.pumpWidget(
      await iconHost(
        apps: [
          pigeon.InstalledApp(
            packageName: 'com.example.dup',
            appName: 'Dup App One',
            isSystemApp: false,
          ),
          pigeon.InstalledApp(
            packageName: 'com.example.dup',
            appName: 'Dup App Two',
            isSystemApp: false,
          ),
        ],
        iconLoader: iconLoader,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byWidgetPredicate((w) => w is Image), findsNWidgets(2));
    expect(callCount, 1);
  });

  // ===============================================================
  // "更多"菜单图标的平台适配（AdaptiveIcon）代表性验证之一：这里用的是
  // `PopupMenuButton(icon: const AdaptiveIcon(...))`，即 Icon Widget 场景
  // （另一种"裸 IconData"场景见 config_options_page_test.dart 里 _PillButton
  // 那条）。用 debugDefaultTargetPlatformOverride mock 平台，不需要真机。
  //
  // 注意：故意拆成两个独立的 testWidgets，而不是在同一个测试里连续切换
  // 平台后两次 pumpWidget——`const AdaptiveIcon(...)` 是编译期常量，Dart
  // 会把同一处 `const` 表达式规约成同一个对象实例；如果在同一个测试里对
  // 同一棵活的 element 树连续 pumpWidget 两次，Flutter 发现新旧 widget是
  // `identical`（同一个 const 对象）就会跳过重新 build，导致图标停留在
  // 第一次渲染的结果上（这是 Flutter 本身"const 优化跳过重建"的行为，不是
  // AdaptiveIcon 的 bug；生产环境里平台不会在运行时变化，const 完全安全）。
  // 每个 testWidgets 之间 flutter_test 会把整棵树卸载重来，不存在这个问题。
  // ===============================================================
  testWidgets('mock 平台为 iOS 时，更多菜单渲染横向三点', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(await _host());
    await tester.pump();

    expect(find.byIcon(FluentIcons.more_horizontal_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('mock 平台为 Android 时，更多菜单渲染纵向三点', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(await _host());
    await tester.pump();

    expect(find.byIcon(FluentIcons.more_vertical_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.more_horizontal_24_regular), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
