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

Future<Widget> _host() async {
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
        home: const ProxiesPage(),
      ),
    ),
  );
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('320 dp、文字 $scale 倍：页头两颗按钮与标题垂直居中且不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      final title = find.text('线路');
      expect(title, findsOneWidget);
      final buttons = find.byType(GlassIconButton);
      expect(buttons, findsNWidgets(2));

      final titleCenter = tester.getCenter(title).dy;
      for (var i = 0; i < 2; i++) {
        final rect = tester.getRect(buttons.at(i));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(
          (rect.center.dy - titleCenter).abs(),
          lessThanOrEqualTo(0.5),
          reason: '第 ${i + 1} 颗按钮应与标题垂直居中',
        );
        // 两颗按钮都完整落在屏内。
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.left, greaterThanOrEqualTo(0));
      }
      // 两颗按钮并排、互不重叠，也不压到标题。
      final first = tester.getRect(buttons.at(0));
      final second = tester.getRect(buttons.at(1));
      expect(first.right, lessThanOrEqualTo(second.left));
      expect(tester.getRect(title).right, lessThanOrEqualTo(first.left));
      expect(tester.takeException(), isNull);
    });
  }
}
