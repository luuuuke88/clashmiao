import 'package:clashmiao/app/router/app_routes.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/config/application/network_settings.dart';
import 'package:clashmiao/features/options/presentation/config_options_page.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 记录各 Navigator 上发生的 push / pop，用来断言页面落在哪个 Navigator、先后顺序。
class _RecordingObserver extends NavigatorObserver {
  final events = <String>[];
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    events.add('push ${route.runtimeType}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      events.add('pop ${route.runtimeType}');
}

void main() {
  testWidgets('真实弹层入口：配置选项页压在根 Navigator 的弹层之上，返回后同一张弹层仍在且可交互', (tester) async {
    // 320×640、2.0× 文字：弹层内容比视口高，弹层自带的滚动位置就是「弹层本地状态」。
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      'clashmiao_set_system_proxy': true,
      'clashmiao_enable_tun': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    final rootObserver = _RecordingObserver();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppRouteScope(
          builders: appRouteBuilders,
          child: ToastificationWrapper(
            child: MaterialApp(
              theme: ThemeData.light().copyWith(
                splashFactory: NoSplash.splashFactory,
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              navigatorObservers: [rootObserver],
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      // 与首页同一个入口。
                      onPressed: () => QuickSettingsModal.show(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheetRoute = rootObserver.pushed.last;
    expect(sheetRoute, isA<ModalBottomSheetRoute<void>>());
    final scrollableFinder = find
        .descendant(
          of: find.byType(QuickSettingsModal),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollableState = tester.state<ScrollableState>(scrollableFinder);

    // 滚到末项，再点进「所有进阶选项」。
    final last = find.text('所有进阶选项');
    for (var i = 0; i < 4 && last.hitTestable().evaluate().isEmpty; i++) {
      await tester.fling(scrollableFinder, const Offset(0, -500), 2500);
      await tester.pumpAndSettle();
    }
    expect(last.hitTestable(), findsOneWidget);
    final offsetBefore = scrollableState.position.pixels;
    expect(offsetBefore, greaterThan(0), reason: '前置条件：弹层确实滚动过');

    await tester.tap(last);
    await tester.pumpAndSettle();

    // 配置选项页在根 Navigator 上，压在弹层路由之上。
    final pageRoute = rootObserver.pushed.last;
    expect(pageRoute, isA<MaterialPageRoute<void>>());
    expect(pageRoute.navigator, same(sheetRoute.navigator));
    expect(pageRoute.isCurrent, isTrue);
    expect(sheetRoute.isActive, isTrue, reason: '弹层路由仍在栈里，没有被换掉');
    expect(sheetRoute.isCurrent, isFalse);
    expect(find.byType(ConfigOptionsPage), findsOneWidget);

    // 返回：关掉配置选项页，露出的还是同一张弹层。
    Navigator.of(
      tester.element(find.byType(ConfigOptionsPage)),
      rootNavigator: true,
    ).pop();
    await tester.pumpAndSettle();

    expect(find.byType(ConfigOptionsPage), findsNothing);
    expect(sheetRoute.isCurrent, isTrue);
    expect(
      rootObserver.pushed.whereType<ModalBottomSheetRoute<void>>().length,
      1,
      reason: '没有重新打开过第二张弹层',
    );
    expect(find.byType(QuickSettingsModal), findsOneWidget);
    // 同一个 Scrollable 状态对象、同一个滚动位置：弹层没有被重建。
    expect(
      tester.state<ScrollableState>(scrollableFinder),
      same(scrollableState),
    );
    expect(scrollableState.position.pixels, offsetBefore);

    // 仍可交互：滚回顶部后点 TLS 开关能写入设置。
    await tester.fling(scrollableFinder, const Offset(0, 800), 2500);
    await tester.pumpAndSettle();
    expect(container.read(networkSettingsProvider).enableTlsFragment, isFalse);
    await tester.tap(find.text('启用 TLS 数据分段'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
  });

  testWidgets('快速设置点「所有进阶选项」：配置选项页压在根 Navigator 上，返回后弹窗状态不变', (tester) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      'clashmiao_set_system_proxy': true,
      'clashmiao_enable_tun': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    NavigatorState? pushedOn;
    NavigatorState? root;
    final rootKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppRouteScope(
          builders: {
            AppRoute.configOptions: (context) {
              pushedOn = Navigator.of(context);
              root = Navigator.of(context, rootNavigator: true);
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('配置选项页桩'),
                  ),
                ),
              );
            },
          },
          child: ToastificationWrapper(
            child: MaterialApp(
              navigatorKey: rootKey,
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              // 快速设置放在一个嵌套 Navigator 里：不传 rootNavigator 的话
              // 页面会压到嵌套 Navigator，而不是根。
              home: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: QuickSettingsModal()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 先改一个状态，用来验证返回后弹窗没有被重建/重置。
    await tester.tap(find.text('启用 TLS 数据分段'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.text('所有进阶选项'));
    await tester.pumpAndSettle();

    expect(find.text('配置选项页桩'), findsOneWidget);
    expect(pushedOn, isNotNull);
    expect(pushedOn, same(root), reason: '配置选项页必须压在根 Navigator 上');
    expect(root, same(rootKey.currentState));

    await tester.tap(find.text('配置选项页桩'));
    await tester.pumpAndSettle();

    expect(find.text('配置选项页桩'), findsNothing);
    expect(find.text('快速设置'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
  });
}
