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
      // 服务模式档位按平台分：移动端是 仅线路/VPN，桌面端是 仅线路/系统线路
      // （桌面没有 TUN 驱动和权限，不提供 VPN 档，见 _quickServiceModeChoices）。
      if (Platform.isAndroid || Platform.isIOS) {
        expect(find.text('VPN'), findsOneWidget);
      } else {
        expect(find.text('系统线路'), findsOneWidget);
        expect(find.text('VPN'), findsNothing);
      }
      expect(find.text('启用 WARP'), findsOneWidget);
      expect(find.text('启用 TLS 数据分段'), findsOneWidget);
      expect(find.text('所有进阶选项'), findsOneWidget);
      expect(find.text('全局代理'), findsNothing);
      expect(find.text('智能分流'), findsNothing);
      expect(find.text('启用 DNS 路由'), findsNothing);
    });

    // 三个档位对应的是 setSystemProxy / enableTun 两个 bool 的组合，任意时刻
    // 只能有一个为 true。可选档位按平台不同（桌面没有 VPN 档），所以互斥性
    // 分两条路径验证，验的是同一条不变量。
    testWidgets('服务模式切换会保持系统线路和 VPN 互斥（移动端）', (tester) async {
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
    }, skip: !Platform.isAndroid && !Platform.isIOS);

    testWidgets('服务模式切换会保持仅线路和系统线路互斥（桌面端）', (tester) async {
      final (widget, container) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('仅线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isFalse);
      expect(container.read(networkSettingsProvider).enableTun, isFalse);

      await tester.tap(find.text('系统线路'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(container.read(networkSettingsProvider).setSystemProxy, isTrue);
      expect(
        container.read(networkSettingsProvider).enableTun,
        isFalse,
        reason: '桌面端任何档位都不该把 enableTun 打开——没有驱动和权限支撑它',
      );
    }, skip: Platform.isAndroid || Platform.isIOS);

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

    // 桌面端仓库里不带 wintun 驱动，macOS 也没有网络扩展权限/特权 helper，
    // 选了 TUN 只会让内核起 tun 设备失败。给用户一个必定失败的选项，比不给
    // 这个选项糟糕得多。测试跑在 macOS 宿主上，正好覆盖桌面分支。
    testWidgets('桌面端不提供 TUN 服务模式（选了必定失败的选项不该出现）', (tester) async {
      final (widget, _) = await _host();
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('仅线路'), findsWidgets, reason: '前置条件：服务模式选择器要真的渲染出来了');
      expect(find.text('系统线路'), findsWidgets, reason: '桌面端唯一真正能用的接管方式');
      expect(find.text('VPN'), findsNothing, reason: '桌面端没有 TUN 驱动/权限，不能给这个档位');
    }, skip: Platform.isAndroid || Platform.isIOS);
  });
}
