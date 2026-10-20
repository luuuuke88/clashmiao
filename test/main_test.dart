import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/main.dart'
    show
        DesktopShutdownGuard,
        bootstrapSentryGatedApp,
        listenResidentServices,
        residentServiceProviders;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 回归测试：桌面端点击窗口关闭按钮曾经会直接 disconnect() + destroy()，
/// 断开 VPN 并彻底退出进程，而不是按系统托盘应用的标准行为隐藏到托盘。
///
/// 见 lib/main.dart 的 `DesktopShutdownGuard`（曾经叫 `_DesktopShutdownGuard`，
/// `onWindowClose` 里直接调 `connectionControllerProvider.notifier.disconnect()`
/// 再 `windowManager.destroy()`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopShutdownGuard', () {
    test('onWindowClose 只隐藏窗口到托盘，绝不 destroy/close 进程', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('window_manager'), (
            call,
          ) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('window_manager'),
              null,
            );
      });

      DesktopShutdownGuard().onWindowClose();
      // onWindowClose 内部是 async 但没人 await 它（WindowListener 回调签名如此），
      // 让 microtask 队列先跑完，确保 hide() 的 invokeMethod 已经落地。
      await Future<void>.delayed(Duration.zero);

      expect(calls, contains('hide'), reason: '点击关闭按钮必须隐藏窗口到系统托盘');
      expect(
        calls,
        isNot(anyElement(anyOf(equals('destroy'), equals('close')))),
        reason:
            '绝不能调用 destroy/close 退出进程或关闭原生窗口——'
            '这正是本次修复的 bug：点关闭按钮不应该退出程序',
      );
    });
  });

  group('bootstrapSentryGatedApp', () {
    // 回归测试：数据分析开关（`clashmiao_analytics_enabled`，默认 false，
    // opt-in）曾经跟 Sentry SDK 是否初始化完全无关——main.dart 只要编译期
    // SENTRY_DSN 非空就无条件 SentryFlutter.init，用户关掉开关后未处理异常
    // 依然被自动上报，隐私承诺和实际行为不符。现在 Sentry.init 只在
    // "DSN 非空 且 用户勾选了数据分析开关" 同时成立时才真正调用。

    test('analytics 开关为 false 时，绝不调用 initSentry，只跑 appRunner', () async {
      var initSentryCalls = 0;
      var appRunnerCalls = 0;

      await bootstrapSentryGatedApp(
        dsn: 'https://fake@example.com/1',
        analyticsEnabled: false,
        initSentry: (dsn, appRunner) async {
          initSentryCalls++;
          appRunner();
        },
        appRunner: () => appRunnerCalls++,
      );

      expect(initSentryCalls, 0, reason: '开关关闭时 Sentry SDK 完全不应该被初始化');
      expect(appRunnerCalls, 1, reason: 'App 该跑的还是要跑，只是不接入 Sentry');
    });

    test('analytics 开关为 true 且 DSN 非空时，真正调用 initSentry', () async {
      var initSentryCalls = 0;
      var appRunnerCalls = 0;
      String? receivedDsn;

      await bootstrapSentryGatedApp(
        dsn: 'https://fake@example.com/1',
        analyticsEnabled: true,
        initSentry: (dsn, appRunner) async {
          initSentryCalls++;
          receivedDsn = dsn;
          appRunner();
        },
        appRunner: () => appRunnerCalls++,
      );

      expect(initSentryCalls, 1, reason: '开关打开且编译期有 DSN 时必须真正初始化 Sentry');
      expect(receivedDsn, 'https://fake@example.com/1');
      expect(appRunnerCalls, 1);
    });

    test('analytics 开关为 true 但编译期 DSN 为空时，仍然不调用 initSentry', () async {
      var initSentryCalls = 0;
      var appRunnerCalls = 0;

      await bootstrapSentryGatedApp(
        dsn: '',
        analyticsEnabled: true,
        initSentry: (dsn, appRunner) async {
          initSentryCalls++;
          appRunner();
        },
        appRunner: () => appRunnerCalls++,
      );

      expect(
        initSentryCalls,
        0,
        reason: '没编译进 DSN 时 Sentry SDK 根本不存在，开关打开也不该假装调用',
      );
      expect(appRunnerCalls, 1);
    });
  });

  group('常驻服务（Riverpod 3 暂停语义）', () {
    test('启动时常驻的 provider 清单：内部靠 ref.listen 驱动的服务一个不能少', () {
      expect(
        residentServiceProviders,
        containsAll(<Object>[
          deepLinkServiceProvider,
          connectionControllerProvider,
          egressIpProbeProvider,
          connectionHealthProvider,
          latencyTestCoordinatorProvider,
          boxStatsProvider,
        ]),
      );
    });

    // 用最小的 provider 链复现生产里的结构：服务在 build 里 ref.listen 一个
    // 派生 provider（对应 activeProfileProvider），派生值变化时做事（对应
    // 「删除激活订阅 → 断开」）。派生 provider 只有在被活跃监听时才会重算。
    final source = NotifierProvider<_Counter, int>(_Counter.new);
    final derived = Provider<int>((ref) => ref.watch(source));
    late List<int> seen;
    final service = Provider<Object>((ref) {
      ref.listen<int>(derived, (_, next) => seen.add(next));
      return Object();
    });

    setUp(() => seen = []);

    test('只 read 一次的服务处于暂停状态，内部 ref.listen 收不到上游变化', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(service);
      container.read(source.notifier).bump();
      await pumpEventQueue();

      expect(seen, isEmpty, reason: '这正是 main() 不能只 read 的原因');
    });

    test('listenResidentServices 建的容器级监听让服务保持活跃', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final subs = listenResidentServices(container, [service]);
      container.read(source.notifier).bump();
      await pumpEventQueue();

      expect(seen, [1]);
      expect(subs.single.isPaused, isFalse);
    });
  });
}

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
