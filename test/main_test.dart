import 'package:clashmiao/main.dart'
    show DesktopShutdownGuard, bootstrapSentryGatedApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
