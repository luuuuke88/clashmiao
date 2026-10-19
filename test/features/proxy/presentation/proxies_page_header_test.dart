import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_box_service.dart';

/// GlassIconButton 的交互区放大到 48x48 之后，页头里两颗按钮占的高度比标题大。
/// 这里在窄屏 320 dp、字号 1.0x / 2.0x 下断言：两颗按钮仍与标题垂直居中对齐，
/// 且页头不溢出。
const _profile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

Future<Widget> _host(TextDirection direction) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _profile),
      boxServiceProvider.overrideWithValue(const FakeBoxService()),
      offlineProxyGroupsProvider.overrideWith(
        (_) async => const [
          OutboundGroup(
            tag: 'proxy',
            type: 'selector',
            selected: 'node-a',
            items: [OutboundProxy(tag: 'node-a', type: 'shadowsocks')],
          ),
        ],
      ),
      isConnectedProvider.overrideWith((_) => false),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        builder: (context, child) =>
            Directionality(textDirection: direction, child: child!),
        home: const ProxiesPage(),
      ),
    ),
  );
}

void main() {
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('320 dp、文字 $scale 倍、${direction.name.toUpperCase()}：'
          '页头两颗按钮与标题垂直居中、在屏内、互不重叠且不溢出', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(await _host(direction));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));

        final title = find.text('线路');
        expect(title, findsOneWidget);
        final buttons = find.byType(GlassIconButton);
        expect(buttons, findsNWidgets(2));

        final titleRect = tester.getRect(title);
        final rects = [
          for (var i = 0; i < 2; i++) tester.getRect(buttons.at(i)),
        ];
        for (var i = 0; i < 2; i++) {
          expect(rects[i].height, greaterThanOrEqualTo(48));
          expect(
            (rects[i].center.dy - titleRect.center.dy).abs(),
            lessThanOrEqualTo(0.5),
            reason: '第 ${i + 1} 颗按钮应与标题垂直居中',
          );
        }

        // 屏内：标题与两颗按钮都完整落在 [0, 320] 里（方向无关）。
        for (final r in [titleRect, ...rects]) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(320));
        }

        // 方向感知的先后：沿「起点 → 末端」依次是 标题、按钮 1、按钮 2，
        // LTR 自左向右，RTL 自右向左，彼此不重叠。
        final ltr = direction == TextDirection.ltr;
        bool before(Rect a, Rect b) =>
            ltr ? a.right <= b.left + 0.5 : a.left >= b.right - 0.5;
        expect(before(titleRect, rects[0]), isTrue, reason: '标题不应压到第 1 颗按钮');
        expect(before(rects[0], rects[1]), isTrue, reason: '两颗按钮不应重叠');
        // 标题贴起点一侧，按钮组贴末端一侧。
        if (ltr) {
          expect(titleRect.left, lessThan(rects[0].left));
        } else {
          expect(titleRect.right, greaterThan(rects[0].right));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
