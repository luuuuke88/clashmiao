import 'dart:ui' show AppExitResponse;

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/app/window/desktop_exit_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/counting_box_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('桌面端退出守卫', () {
    late ProviderContainer container;
    late CountingBoxService box;

    Future<DesktopExitGuard> setUpGuard() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      box = CountingBoxService();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(box),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      final controller = container.read(connectionControllerProvider.notifier);
      // 1.5s 的"断开中"展示动画在测试里没有意义，直接放行。
      controller.disconnectSettleDelay = (_) async {};
      box.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
      return DesktopExitGuard(container);
    }

    test('收到退出请求必须真的停内核——否则系统代理会永久残留', () async {
      final guard = await setUpGuard();
      expect(box.stopCalls, 0, reason: '前提：还没停');

      final response = await guard.handleExitRequest();

      expect(
        box.stopCalls,
        greaterThanOrEqualTo(1),
        reason:
            '没有停内核。三个桌面平台的系统代理写的都是持久化设置，只在优雅关闭时'
            '还原——漏了这一步，用户按一下 Cmd+Q 之后系统代理就永久指向一个没人'
            '监听的本地端口，整机浏览器断网',
      );
      expect(response, AppExitResponse.exit);
    });

    test('停内核失败也必须放行退出，绝不能把 App 卡在退不出去的状态', () async {
      final guard = await setUpGuard();
      box.stopError = StateError('模拟内核停止失败');

      final response = await guard.handleExitRequest();

      expect(
        response,
        AppExitResponse.exit,
        reason:
            '返回 cancel 或者抛异常会让 App 退不出去，用户只能强制退出——'
            '而强制退出恰好跳过清理，等于把要修的问题变得更糟',
      );
      expect(box.stopCalls, greaterThanOrEqualTo(1));
    });

    test('清理卡住时超时放行，不无限等待', () async {
      final guard = await setUpGuard();
      // 让 stop() 永远不返回，模拟内核完全无响应。
      box.stopHangs = true;

      final sw = Stopwatch()..start();
      final response = await guard.handleExitRequest();
      sw.stop();

      expect(response, AppExitResponse.exit);
      expect(
        sw.elapsed,
        lessThan(kDesktopExitCleanupTimeout + const Duration(seconds: 2)),
        reason: '超时保护没生效，退出会被无限期挂住',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('install/dispose 可重复调用，不抛', () async {
      final guard = await setUpGuard();
      guard.install();
      guard.dispose();
      guard.dispose();
    });
  });
}
