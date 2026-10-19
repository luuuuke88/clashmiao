import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:clashmiao/app/window/desktop_exit_guard.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_fakes/fake_kernel_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('桌面端退出守卫', () {
    late ProviderContainer container;
    late FakeKernelPort port;
    late SharedPreferences prefs;
    var version = 0;

    /// 已连接（attached）的环境；[onOff] 决定内核如何响应断开请求。
    Future<DesktopExitGuard> setUpGuard({
      FutureOr<void> Function(DesiredRequest r)? onOff,
      bool dirty = true,
    }) async {
      SharedPreferences.setMockInitialValues({
        if (dirty) kSystemProxyDirtyKey: true,
      });
      prefs = await SharedPreferences.getInstance();
      version = 1;
      port = FakeKernelPort(
        initial: FakeKernelPort.snap(
          version: version,
          status: KernelStatus.started,
          attempt: 1,
          desired: Desired.on,
          activeConfigRevision: 1,
        ),
      );
      port.onRequest = (r) async {
        if (r.desired == Desired.off) await onOff?.call(r);
      };
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          kernelPortProvider.overrideWithValue(port),
          isDesktopPlatformProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      container.read(connectionControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(connectionControllerProvider).phase,
        ConnectionPhase.connected,
        reason: '前提：已连接',
      );
      return DesktopExitGuard(container);
    }

    /// 内核停下：推一份 stopped 快照，appliedSeq 追上 [r]。
    void kernelStops(DesiredRequest r) {
      port.push(
        FakeKernelPort.snap(
          version: ++version,
          status: KernelStatus.stopped,
          attempt: 1,
          desired: Desired.off,
          source: DesiredSource.app,
          appliedSeq: r.seq,
        ),
      );
    }

    test('收到退出请求必须真的停内核——否则系统代理会永久残留；确认停止后清脏标记', () async {
      final guard = await setUpGuard(onOff: kernelStops);
      expect(port.requests, isEmpty, reason: '前提：还没发断开');

      final response = await guard.handleExitRequest();

      expect(
        port.requests.map((r) => r.desired),
        contains(Desired.off),
        reason:
            '没有停内核。三个桌面平台的系统代理写的都是持久化设置，只在优雅关闭时'
            '还原——漏了这一步，用户按一下 Cmd+Q 之后系统代理就永久指向一个没人'
            '监听的本地端口，整机浏览器断网',
      );
      expect(response, AppExitResponse.exit);
      expect(
        prefs.getBool(kSystemProxyDirtyKey),
        isNull,
        reason: 'succeeded 才清脏标记：内核已确认停止，代理已被还原',
      );
    });

    test('停内核失败（请求发不出去）也必须放行退出；失败不清脏标记，留给下次启动自愈', () async {
      final guard = await setUpGuard();
      port.requestError = StateError('模拟内核停止失败');

      final response = await guard.handleExitRequest();

      expect(
        response,
        AppExitResponse.exit,
        reason:
            '返回 cancel 或者抛异常会让 App 退不出去，用户只能强制退出——'
            '而强制退出恰好跳过清理，等于把要修的问题变得更糟',
      );
      expect(port.requests, isNotEmpty);
      expect(prefs.getBool(kSystemProxyDirtyKey), isTrue);
    });

    test('断开被外部入口覆盖（superseded）时再发一次断开，等最新的结果', () async {
      var offs = 0;
      final guard = await setUpGuard(
        onOff: (r) {
          offs++;
          if (offs == 1) {
            // 第一次断开刚被受理就被磁贴的「开」覆盖：appliedSeq 超过它。
            port.push(
              FakeKernelPort.snap(
                version: ++version,
                status: KernelStatus.started,
                attempt: 2,
                desired: Desired.on,
                source: DesiredSource.tile,
                appliedSeq: r.seq + 1,
                activeConfigRevision: 1,
              ),
            );
          } else {
            kernelStops(r);
          }
        },
      );

      final response = await guard.handleExitRequest();

      expect(response, AppExitResponse.exit);
      expect(
        port.requests.where((r) => r.desired == Desired.off),
        hasLength(2),
        reason: 'superseded 之后必须再发一次断开，不能带着一个仍在运行的内核退出',
      );
      expect(prefs.getBool(kSystemProxyDirtyKey), isNull);
    });

    test('清理卡住时超时放行，不无限等待', () async {
      // 让内核对断开请求永远不应答，模拟完全无响应。
      final hang = Completer<void>();
      final guard = await setUpGuard(onOff: (_) => hang.future);

      final sw = Stopwatch()..start();
      final response = await guard.handleExitRequest();
      sw.stop();

      expect(response, AppExitResponse.exit);
      expect(
        sw.elapsed,
        lessThan(kDesktopExitCleanupTimeout + const Duration(seconds: 2)),
        reason: '超时保护没生效，退出会被无限期挂住',
      );
      expect(prefs.getBool(kSystemProxyDirtyKey), isTrue, reason: '没确认停止就不清标记');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('install/dispose 可重复调用，不抛', () async {
      final guard = await setUpGuard();
      guard.install();
      guard.dispose();
      guard.dispose();
    });
  });
}
