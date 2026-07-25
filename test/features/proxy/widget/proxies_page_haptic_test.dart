import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/box_service.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/model/profile_entity.dart';
import 'package:clashmiao/features/proxy/widget/proxies_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 覆盖：wave4 触觉反馈扩展——代理节点切换 / 测速两个交互点。
///
/// 复用 `proxies_page_tap_test.dart` 的 `_SpyBoxService` + host 搭建模式，
/// 额外 mock `SystemChannels.platform` 记录 `HapticFeedback.vibrate` 调用
/// （跟 `test/core/haptic/haptic_service_test.dart` 的验证方式一致），这样
/// 既能验证"确实调用了 HapticService"，又能验证"偏好读取"这一层真实生效
/// （不是绕过 HapticService 直接 spy 调用次数）。
class _SpyBoxService implements BoxService {
  int selectOutboundCalls = 0;
  final List<String> urlTestCalls = [];

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) async {
    selectOutboundCalls++;
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> setup(AppDirectories d, {bool debug = false}) async {}
  @override
  Future<String?> validateConfig(
    String a,
    String b, {
    bool debug = false,
  }) async => null;
  @override
  Future<void> changeConfigOptions(String jsonOptions) async {}
  @override
  Future<void> start(String path, {String name = ''}) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> restart(String path, {String name = ''}) async {}
  @override
  Future<void> urlTest(String g) async {
    urlTestCalls.add(g);
  }

  @override
  Stream<BoxStatus> watchStatus() => const Stream.empty();
  @override
  Stream<BoxAlert> watchAlerts() => const Stream.empty();
  @override
  Stream<BoxStats> watchStats() => const Stream.empty();
  @override
  Stream<List<OutboundGroup>> watchGroups() => const Stream.empty();
  @override
  Future<String?> generateFullConfig(String p) async => null;
  @override
  Future<String?> generateWarpConfig({
    required String licenseKey,
    String? previousAccountId,
    String? previousAccessToken,
  }) async => null;
  @override
  Future<void> clearLogs() async {}
  @override
  Stream<List<String>> watchLogs(String p) => const Stream.empty();
  @override
  Stream<void> watchNetworkChanged() => const Stream.empty();
  @override
  Future<void> resetTunnel() async {}
}

const _ssNode = OutboundProxy(tag: 'ss-node', type: 'shadowsocks');
const _activeProfile = ProfileEntity(
  id: 'profile-1',
  name: '测试订阅',
  url: 'https://example.com/sub',
  active: true,
);

OutboundGroup _proxyGroup() => const OutboundGroup(
  tag: 'proxy',
  type: 'selector',
  selected: 'ss-node',
  items: [_ssNode],
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
}

/// 平台通道在 pump 一个完整 MaterialApp 期间还会收到跟触觉反馈无关的调用
/// （比如 `SystemChrome.setApplicationSwitcherDescription`），不能直接断言
/// 整个 `calls` 列表为空，只筛出 `HapticFeedback.vibrate` 这一种方法。
Iterable<MethodCall> _hapticCalls(List<MethodCall> calls) =>
    calls.where((c) => c.method == 'HapticFeedback.vibrate');

Future<(Widget, _SpyBoxService)> _host({
  required bool connected,
  bool hapticEnabled = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    'clashmiao_haptic_feedback': hapticEnabled,
  });
  final prefs = await SharedPreferences.getInstance();
  final spy = _SpyBoxService();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      activeProfileProvider.overrideWith((_) async => _activeProfile),
      boxServiceProvider.overrideWithValue(spy),
      offlineProxyGroupsProvider.overrideWith((_) async => [_proxyGroup()]),
      isConnectedProvider.overrideWith((_) => connected),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  return (
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const ProxiesPage(),
        ),
      ),
    ),
    spy,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('代理节点切换的触觉反馈', () {
    testWidgets('已连接时点击代理节点触发轻度触觉反馈', (tester) async {
      final (widget, spy) = await _host(connected: true);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('ss-node'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.selectOutboundCalls, 1);
      expect(
        _hapticCalls(
          calls,
        ).where((c) => c.arguments == 'HapticFeedbackType.lightImpact'),
        hasLength(1),
      );
      await _drainToasts(tester);
    });

    testWidgets('触觉反馈偏好关闭时点击代理节点不触发平台调用', (tester) async {
      final (widget, spy) = await _host(connected: true, hapticEnabled: false);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('ss-node'));
      await tester.pump(const Duration(milliseconds: 300));

      // 切换行为本身不受偏好影响，只有触觉反馈被静音。
      expect(spy.selectOutboundCalls, 1);
      expect(_hapticCalls(calls), isEmpty);
      await _drainToasts(tester);
    });

    testWidgets('未连接时点击代理节点不触发触觉反馈（只提示不可切换）', (tester) async {
      final (widget, spy) = await _host(connected: false);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('ss-node'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.selectOutboundCalls, 0);
      expect(_hapticCalls(calls), isEmpty);
      await _drainToasts(tester);
    });
  });

  group('代理测速的触觉反馈', () {
    testWidgets('已连接时点测速按钮触发轻度触觉反馈', (tester) async {
      final (widget, spy) = await _host(connected: true);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.urlTestCalls, isNotEmpty);
      expect(
        _hapticCalls(
          calls,
        ).where((c) => c.arguments == 'HapticFeedbackType.lightImpact'),
        hasLength(1),
      );

      // 让测速动画完整跑完，避免残留 Future/Timer。
      await tester.pump(const Duration(milliseconds: 1600));
      await _drainToasts(tester);
    });

    testWidgets('触觉反馈偏好关闭时点测速按钮不触发平台调用', (tester) async {
      final (widget, spy) = await _host(connected: true, hapticEnabled: false);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.urlTestCalls, isNotEmpty);
      expect(_hapticCalls(calls), isEmpty);

      await tester.pump(const Duration(milliseconds: 1600));
      await _drainToasts(tester);
    });

    testWidgets('未连接时点测速按钮不触发触觉反馈（只提示需先连接）', (tester) async {
      final (widget, spy) = await _host(connected: false);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byIcon(FluentIcons.flash_24_regular));
      await tester.pump(const Duration(milliseconds: 300));

      expect(spy.urlTestCalls, isEmpty);
      expect(_hapticCalls(calls), isEmpty);
      await _drainToasts(tester);
    });
  });
}
