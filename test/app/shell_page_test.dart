import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/deep_link/deep_link_service.dart';
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

Future<(Widget, ProviderContainer)> _host({
  List<Override> extraOverrides = const [],
}) async {
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
      boxServiceProvider.overrideWithValue(StubBoxService()),
      profileListProvider.overrideWith((_) => Future.value(const [])),
      activeProfileProvider.overrideWith((_) => Future.value(null)),
      offlineProxyGroupsProvider.overrideWith((_) => Future.value(const [])),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
      boxStatsProvider.overrideWith((_) => Stream.value(BoxStats.empty)),
      ...extraOverrides,
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(profileListProvider.future);
  await container.read(activeProfileProvider.future);

  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const ShellPage(),
        ),
      ),
    ),
    container,
  );
}

/// 跟 app_toast_test.dart 的 `_drainToasts` 保持一致：把 autoCloseDuration
/// 耗尽再 dismissAll，避免 pending timer 泄漏到下一个 test。
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'ShellPage 保持 4 项玻璃底部导航',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final (widget, container) = await _host();
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 300));

      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey('bottom_nav_$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('bottom_nav_4')), findsNothing);
      expect(container.read(selectedTabProvider), AppTab.home);

      await tester.tap(find.byKey(const ValueKey('bottom_nav_1')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(selectedTabProvider), AppTab.proxies);

      await tester.tap(find.byKey(const ValueKey('bottom_nav_2')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(selectedTabProvider), AppTab.settings);

      await tester.tap(find.byKey(const ValueKey('bottom_nav_3')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(container.read(selectedTabProvider), AppTab.about);
    },
  );

  testWidgets('深链运行时导入成功 → ShellPage 弹出成功 toast', (tester) async {
    final (widget, container) = await _host();
    addTearDown(container.dispose);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    // 模拟 DeepLinkService 在 App 运行中处理完一条深链、写入结果。
    container.read(deepLinkImportResultProvider.notifier).state =
        const DeepLinkImportSuccess('我的测试订阅');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('已导入订阅：我的测试订阅'), findsOneWidget);
    // 消费后应重置回 null，避免下次重建重复弹出。
    expect(container.read(deepLinkImportResultProvider), isNull);

    await _drainToasts(tester);
  });

  testWidgets('深链导入失败 → ShellPage 弹出错误 toast', (tester) async {
    final (widget, container) = await _host();
    addTearDown(container.dispose);

    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    container.read(deepLinkImportResultProvider.notifier).state =
        const DeepLinkImportFailure('深链缺少订阅地址参数');
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    expect(find.text('导入订阅失败：深链缺少订阅地址参数'), findsOneWidget);

    await _drainToasts(tester);
  });

  testWidgets(
    '冷启动时序兜底：ShellPage 挂载前就已经产生的深链结果，'
    '首次 build 后也会补显示 toast',
    (tester) async {
      // 覆盖成"挂载前就已经有一个待展示的结果"，模拟 DeepLinkService 在
      // ShellPage 完成挂载之前就已经处理完冷启动链接的时序竞争。
      final (widget, container) = await _host(
        extraOverrides: [
          deepLinkImportResultProvider.overrideWith(
            (ref) => const DeepLinkImportSuccess('冷启动订阅'),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('已导入订阅：冷启动订阅'), findsOneWidget);
      expect(container.read(deepLinkImportResultProvider), isNull);

      await _drainToasts(tester);
    },
  );
}
