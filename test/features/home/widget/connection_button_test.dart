import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:clashmiao/features/home/widget/speed_cat_connection_mark.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
    testWidgets('所有状态的连接按钮都显示猫咪 Logo，不显示通用状态图标', (tester) async {
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
        expect(
          find.byIcon(FluentIcons.shield_checkmark_24_regular),
          findsNothing,
        );
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

    testWidgets('Stopped 状态显示"点击连接"且可点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        await _host(const BoxStopped(), onTap: () => tapped++),
      );
      // pump translations future + animation init
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('点击连接'), findsOneWidget);

      await tester.tap(find.byType(ConnectionButton));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('Starting 状态显示"正在连接"', (tester) async {
      await tester.pumpWidget(await _host(const BoxStarting()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('正在连接'), findsOneWidget);
    });

    testWidgets('Started 状态显示"已连接"且 onTap 仍触发（用于断开）', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        await _host(const BoxStarted(), onTap: () => tapped++),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('已连接'), findsOneWidget);

      await tester.tap(find.byType(ConnectionButton));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('Stopping 状态显示"正在断开连接"', (tester) async {
      await tester.pumpWidget(await _host(const BoxStopping()));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('正在断开连接'), findsOneWidget);
    });
  });
}
