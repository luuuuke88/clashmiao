import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/config/presentation/config_options_page.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../support/fake_box_service.dart';
import '../support/toast_pump.dart';

/// 正常手机视口（不是 4000 高的整页）下，2.0× 文字、RTL 的真实滚动验收：
/// 用手势（drag / fling）滚到末项，末项可见且点得到，全程没有异常（含溢出）。
///
/// 与 `text_scale_matrix_test.dart` 互补：那边用超高视口一次建出整页来查溢出，
/// 这边验证真实高度约束、滚动归属与可达性。

const _viewports = <Size>[Size(320, 640), Size(360, 780)];

const _variants = <(String, String, TextDirection)>[
  ('LTR', 'zhCn', TextDirection.ltr),
  ('RTL', 'ar', TextDirection.rtl),
];

const _profile = ProfileEntity(
  id: 'p1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

void _useView(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 记录推入的路由，用来断言「点了入口就真的导航了」。
class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

Future<Widget> _app({
  _PushObserver? observer,
  required String locale,
  required TextDirection direction,
  required Widget home,
  List<Override> overrides = const [],
  // 内核服务替身单独成参：Riverpod 3 下同一个容器里重复 override 同一个
  // provider 是断言失败，要换替身就替换默认值，而不是再追加一条 override。
  BoxService boxService = const StubBoxService(),
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': locale,
    'clashmiao_set_system_proxy': true,
    'clashmiao_enable_tun': false,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(boxService),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          splashFactory: NoSplash.splashFactory,
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        navigatorObservers: [?observer],
        home: home,
      ),
    ),
  );
}

/// 末项在视口内、没有被别的东西盖住（`hitTestable`），并且整体落在屏幕里。
void _expectReachable(WidgetTester tester, Finder item, Size view) {
  expect(item, findsOneWidget);
  expect(item.hitTestable(), findsOneWidget, reason: '末项应当可点（未被遮挡、在视口内）');
  final rect = tester.getRect(item);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(view.height));
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(view.width));
}

void main() {
  for (final view in _viewports) {
    for (final (dirName, locale, direction) in _variants) {
      testWidgets('代理页 / ${view.width.toInt()}×${view.height.toInt()} / 2.0× / '
          '$dirName：手势滚到末项，末项可见且可点', (tester) async {
        _useView(tester, view, 2.0);
        const lastTag = 'Zulu Last 99';
        await tester.pumpWidget(
          await _app(
            locale: locale,
            direction: direction,
            home: const ProxiesPage(),
            boxService: const FakeBoxService(),
            overrides: [
              activeProfileProvider.overrideWith((_) async => _profile),
              isConnectedProvider.overrideWith((_) => false),
              offlineProxyGroupsProvider.overrideWith(
                (_) async => [
                  OutboundGroup(
                    tag: 'proxy',
                    type: 'selector',
                    selected: 'Node 01',
                    items: [
                      const OutboundProxy(tag: 'auto-group', type: 'urltest'),
                      for (var i = 1; i < 40; i++)
                        OutboundProxy(
                          tag: 'Node ${i.toString().padLeft(2, '0')}',
                          type: 'vless',
                        ),
                      const OutboundProxy(tag: lastTag, type: 'trojan'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        // 节点顺序由页面自己的排序决定，测试不假设谁是最后一个：手势一路滚到
        // 列表尽头，沿途收集看到过的节点名，再验证**此刻最靠下的那一行**。
        final nodeName = RegExp(r'^(Node \d\d|Zulu Last 99)$');
        final seen = <String>{};
        void collect() {
          for (final text in tester.widgetList<Text>(find.byType(Text))) {
            final data = text.data;
            if (data != null && nodeName.hasMatch(data)) seen.add(data);
          }
        }

        final list = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(list).position;
        collect();
        expect(position.pixels, 0);
        for (var i = 0; i < 200; i++) {
          if (position.pixels >= position.maxScrollExtent) break;
          // 交替 fling 与 drag：都是真实手势，不用 jumpTo。
          if (i.isEven) {
            await tester.fling(list, const Offset(0, -400), 1800);
            await tester.pumpAndSettle();
          } else {
            await tester.drag(list, const Offset(0, -250));
            await tester.pump();
          }
          collect();
        }
        await tester.pumpAndSettle();
        collect();
        expect(position.pixels, position.maxScrollExtent, reason: '手势应当能滚到尽头');
        // fling 的惯性会跳过中间的行，所以不要求每行都出现过，只要求确实滚动过。
        expect(seen.length, greaterThan(10));

        final last = find
            .byWidgetPredicate(
              (w) => w is Text && w.data != null && nodeName.hasMatch(w.data!),
            )
            .evaluate()
            .map((e) => e.widget as Text)
            .reduce(
              (a, b) =>
                  tester.getRect(find.text(a.data!)).bottom >=
                      tester.getRect(find.text(b.data!)).bottom
                  ? a
                  : b,
            );
        final lastFinder = find.text(last.data!);
        _expectReachable(tester, lastFinder, view);
        await tester.tap(lastFinder);
        await tester.pump(const Duration(milliseconds: 300));
        await pumpToast(tester);
        // 未连接时点节点会弹一条提示 toast：确认点击真的落到了节点上，再收掉它。
        final t = (locale == 'ar' ? AppLocale.ar : AppLocale.zhCn).buildSync();
        expect(find.text(t.proxies.connectBeforeSwitch), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });

      testWidgets('快速设置（QuickSettingsModal.show 真实弹层） / '
          '${view.width.toInt()}×${view.height.toInt()} / 2.0× / $dirName：'
          '手势滚到末项，末项可见且可点', (tester) async {
        _useView(tester, view, 2.0);
        final observer = _PushObserver();
        await tester.pumpWidget(
          await _app(
            observer: observer,
            locale: locale,
            direction: direction,
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => QuickSettingsModal.show(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final t = (locale == 'ar' ? AppLocale.ar : AppLocale.zhCn).buildSync();
        final last = find.text(t.config.allAdvancedOptions);
        expect(find.byType(QuickSettingsModal), findsOneWidget);

        // 弹层里**自带**的滚动（没有再包一层外部滚动）：2.0× 下内容比视口高，
        // 末项一开始在视口外或被裁。
        final scrollable = find.descendant(
          of: find.byType(QuickSettingsModal),
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsWidgets);
        if (view.height <= 640) {
          // 前置条件：矮屏 + 2.0× 下末项一开始确实够不着，滚动是必须的。
          expect(last.hitTestable(), findsNothing);
        }
        for (var i = 0; i < 4 && last.hitTestable().evaluate().isEmpty; i++) {
          await tester.fling(scrollable.first, const Offset(0, -500), 2500);
          await tester.pumpAndSettle();
        }
        if (last.hitTestable().evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            last,
            120,
            scrollable: scrollable.first,
            maxScrolls: 40,
          );
          await tester.pumpAndSettle();
        }

        _expectReachable(tester, last, view);
        // 真的点它：应当导航到高级选项页（配置页在 2.0× 下也不溢出，见文字矩阵）。
        final pushedBefore = observer.pushed.length;
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(
          observer.pushed.length,
          greaterThan(pushedBefore),
          reason: '点击末项应当推入新路由',
        );
        expect(observer.pushed.last, isA<MaterialPageRoute<void>>());
        expect(find.byType(ConfigOptionsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
