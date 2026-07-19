import 'dart:io';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/quick_settings_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<(Widget, ProviderContainer)> _host({
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    'clashmiao_set_system_proxy': true,
    'clashmiao_enable_tun': false,
    ...initialPrefs,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);

  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const Scaffold(body: QuickSettingsModal()),
        ),
      ),
    ),
    container,
  );
}

void main() {
  group('QuickSettingsModal smoke', () {
    testWidgets('渲染快速设置面板', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('快速设置'), findsOneWidget);
      expect(find.text('仅线路'), findsOneWidget);
      if (!Platform.isAndroid && !Platform.isIOS) {
        expect(find.text('系统线路'), findsOneWidget);
      }
      expect(find.text('VPN'), findsOneWidget);
      expect(find.text('启用 WARP'), findsOneWidget);
      expect(find.text('启用 TLS 数据分段'), findsOneWidget);
      expect(find.text('所有进阶选项'), findsOneWidget);
      expect(find.text('全局代理'), findsNothing);
      expect(find.text('智能分流'), findsNothing);
      expect(find.text('启用 DNS 路由'), findsNothing);
    });

    testWidgets('服务模式切换会保持系统线路和 VPN 互斥', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('VPN'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isTrue);

      await tester.tap(find.text('仅线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);
    });

    testWidgets('TLS Fragment 开关写入网络设置', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        container.read(networkSettingsProvider).enableTlsFragment,
        isFalse,
      );

      await tester.tap(find.text('启用 TLS 数据分段'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
    });

    testWidgets('已有 WARP 授权时 WARP 开关写入网络设置', (tester) async {
      final (widget, container) = await _host(
        initialPrefs: {
          'clashmiao_warp_consent_given': true,
          'clashmiao_enable_warp': false,
        },
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).enableWarp, isFalse);

      await tester.tap(find.text('启用 WARP'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).enableWarp, isTrue);
    });
  });
}
