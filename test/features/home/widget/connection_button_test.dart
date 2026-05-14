import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 把 ConnectionButton 放进可渲染的最小宿主：
/// 显式锁定 zh-CN locale，用 ProviderContainer 预读
/// sharedPreferencesProvider，再用 UncontrolledProviderScope 装载，
/// 这样第一帧 build 时 translationsProvider 链路已经 ready。
Future<Widget> _host(BoxStatus status, {VoidCallback? onTap}) async {
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
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Scaffold(
        body: ConnectionButton(status: status, onTap: onTap ?? () {}),
      ),
    ),
  );
}

void main() {
  group('ConnectionButton', () {
    testWidgets('Stopped 状态显示"点击连接"且可点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        await _host(const BoxStopped(), onTap: () => tapped++),
      );
      // pump translations future + animation init
      // 不能 pumpAndSettle：动画是无限循环的（涟漪 / 同步图标），settle 不会到。
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('点击连接'), findsOneWidget);

      await tester.tap(find.byType(ConnectionButton));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('Starting 状态显示"正在连接"', (tester) async {
      await tester.pumpWidget(await _host(const BoxStarting()));
      // 不能 pumpAndSettle：动画是无限循环的（涟漪 / 同步图标），settle 不会到。
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('正在连接'), findsOneWidget);
    });

    testWidgets('Started 状态显示"已连接"且 onTap 仍触发（用于断开）', (tester) async {
      var tapped = 0;
      // Started 触发 flutter_animate 的 ripple，会留 pending timer，
      // 必须用 runAsync 让 real time 流过、timer 真正 fire。
      await tester.runAsync(() async {
        await tester.pumpWidget(
          await _host(const BoxStarted(), onTap: () => tapped++),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('已连接'), findsOneWidget);

        await tester.tap(find.byType(ConnectionButton));
        await tester.pump();
        expect(tapped, 1);

        // 给 ripple timer 一个完整周期，pumpWidget 卸载后让 it fire 一次即完成。
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    });

    testWidgets('Stopping 状态显示"正在断开连接"', (tester) async {
      await tester.pumpWidget(await _host(const BoxStopping()));
      // 不能 pumpAndSettle：动画是无限循环的（涟漪 / 同步图标），settle 不会到。
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('正在断开连接'), findsOneWidget);
    });
  });
}
