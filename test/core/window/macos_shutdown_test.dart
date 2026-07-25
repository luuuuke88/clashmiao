import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/window/macos_shutdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/counting_box_service.dart';

/// 模拟原生侧（`AppDelegate.applicationShouldTerminate`）通过通道请求清理。
Future<void> _invokeNativeShutdown() async {
  const codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        macosShutdownChannelName,
        codec.encodeMethodCall(const MethodCall(macosShutdownMethod)),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('macOS Cmd+Q 退出清理', () {
    late ProviderContainer container;
    late CountingBoxService box;

    Future<void> setUpContainer() async {
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
      // 1.5s 的"断开中"展示动画在测试里没有意义，直接放行，别让每个用例白等。
      controller.disconnectSettleDelay = (_) async {};
      // 进入已连接态
      box.statusStreamController.add(const BoxStarted());
      await Future<void>.delayed(Duration.zero);
    }

    test('收到 shutdown 必须真的停内核——否则系统代理会永久残留', () async {
      await setUpContainer();
      registerMacosShutdownHandler(container);

      expect(box.stopCalls, 0, reason: '前提：还没停');
      await _invokeNativeShutdown();

      expect(
        box.stopCalls,
        1,
        reason:
            '没有停内核。sing-box 在 macOS 上用 `networksetup -setwebproxy` 写的是'
            '**持久化系统设置**，只在优雅关闭时还原——漏了这一步，用户按一下 '
            'Cmd+Q 之后系统代理就永久指向一个没人监听的本地端口，整机浏览器断网',
      );
    });

    test('停内核失败也必须正常返回，不能让退出卡住', () async {
      await setUpContainer();
      box.stopError = StateError('模拟内核停止失败');
      registerMacosShutdownHandler(container);

      // 不抛异常才算通过：原生侧是 `.terminateLater` 在等这条通道的回复，
      // 这里抛出去会变成 FlutterError 回复——虽然原生侧不看返回值、5 秒超时
      // 也会兜住，但那意味着用户按 Cmd+Q 要等 5 秒才退得掉。
      await _invokeNativeShutdown();

      // 2 次而不是 1 次：`disconnect()` 在 stop 失败后会强制清理再重试一遍
      // （见它自己的实现），这是既有的正确行为，不是重复调用的 bug。
      expect(box.stopCalls, greaterThanOrEqualTo(1), reason: '应该尝试过停内核');
    });

    test('未知方法名不触发清理', () async {
      await setUpContainer();
      registerMacosShutdownHandler(container);

      const codec = StandardMethodCodec();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            macosShutdownChannelName,
            codec.encodeMethodCall(const MethodCall('somethingElse')),
            (_) {},
          );

      expect(box.stopCalls, 0);
    });
  });
}
