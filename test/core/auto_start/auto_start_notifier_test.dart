import 'dart:io';

import 'package:clashmiao/core/auto_start/auto_start_notifier.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.clashmiao/auto_start');

/// 假后端，让 Windows/宏观分发逻辑可以在任何宿主机（包括这台 macOS 开发机、
/// CI 的 ubuntu-latest test-unit job）上测试，而不用真的碰
/// `launch_at_startup` 背后的注册表 / LaunchAgents / autostart 文件——那些是
/// 根据*运行测试的真实宿主机* dart:io Platform 分发的全局单例，在非 Windows
/// 机器上调用会要么崩溃（win32_registry FFI）要么写脏宿主机真实文件。
class _FakeAutoStartBackend implements AutoStartBackend {
  bool enabled = false;
  int isEnabledCalls = 0;
  final setEnabledCalls = <bool>[];
  Object? throwOnSetEnabled;

  @override
  Future<bool> isEnabled() async {
    isEnabledCalls++;
    return enabled;
  }

  @override
  Future<void> setEnabled(bool value) async {
    setEnabledCalls.add(value);
    if (throwOnSetEnabled != null) {
      throw throwOnSetEnabled!;
    }
    enabled = value;
  }
}

/// 假 launch_at_startup API，验证 [WindowsAutoStartBackend] 真的把
/// enable/disable/isEnabled 转发给 launch_at_startup（此前 Windows 分支
/// 完全没实现，`_init`/`toggle` 对非 macOS 直接 return，开关在 UI 上能点但
/// 点了毫无效果——见 lib/features/settings/widget/settings_page.dart:195
/// 门禁条件包含 Windows，但通知器只服务 macOS 的历史 bug）。
class _FakeWindowsLaunchAtStartupApi implements WindowsLaunchAtStartupApi {
  bool enabled = false;
  String? setupAppName;
  String? setupAppPath;
  int enableCalls = 0;
  int disableCalls = 0;
  int isEnabledCalls = 0;

  @override
  void setup({required String appName, required String appPath}) {
    setupAppName = appName;
    setupAppPath = appPath;
  }

  @override
  Future<bool> isEnabled() async {
    isEnabledCalls++;
    return enabled;
  }

  @override
  Future<bool> enable() async {
    enableCalls++;
    enabled = true;
    return true;
  }

  @override
  Future<bool> disable() async {
    disableCalls++;
    enabled = false;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoStartNotifier 通过注入的 backend 抽象（跨平台，不依赖真实宿主机 Platform）', () {
    test('init 调用 backend.isEnabled 并同步 state', () async {
      final backend = _FakeAutoStartBackend()..enabled = true;
      final n = AutoStartNotifier(debugBackend: backend);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(backend.isEnabledCalls, 1);
      expect(n.state, isTrue);
    });

    test('toggle false → true 调用 backend.setEnabled(true) 并翻转 state', () async {
      final backend = _FakeAutoStartBackend();
      final n = AutoStartNotifier(debugBackend: backend);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isFalse);
      await n.toggle();
      expect(backend.setEnabledCalls, [true]);
      expect(n.state, isTrue);
    });

    test('backend 抛错时保持当前 state', () async {
      final backend = _FakeAutoStartBackend()
        ..enabled = true
        ..throwOnSetEnabled = Exception('boom');
      final n = AutoStartNotifier(debugBackend: backend);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isTrue);
      await n.toggle();
      expect(n.state, isTrue);
    });

  });

  group('WindowsAutoStartBackend（真正的 Windows 开机自启动实现）', () {
    test('构造时用 appName/appPath 调 launch_at_startup 的 setup', () {
      final api = _FakeWindowsLaunchAtStartupApi();
      WindowsAutoStartBackend(api: api, appName: 'ClashMiao', appPath: 'C:\\x.exe');
      expect(api.setupAppName, 'ClashMiao');
      expect(api.setupAppPath, 'C:\\x.exe');
    });

    test('isEnabled 转发给 launch_at_startup.isEnabled', () async {
      final api = _FakeWindowsLaunchAtStartupApi()..enabled = true;
      final backend = WindowsAutoStartBackend(
        api: api,
        appName: 'ClashMiao',
        appPath: 'C:\\x.exe',
      );
      expect(await backend.isEnabled(), isTrue);
      expect(api.isEnabledCalls, 1);
    });

    test('setEnabled(true) 调 enable，setEnabled(false) 调 disable', () async {
      final api = _FakeWindowsLaunchAtStartupApi();
      final backend = WindowsAutoStartBackend(
        api: api,
        appName: 'ClashMiao',
        appPath: 'C:\\x.exe',
      );
      await backend.setEnabled(true);
      expect(api.enableCalls, 1);
      expect(api.disableCalls, 0);

      await backend.setEnabled(false);
      expect(api.enableCalls, 1);
      expect(api.disableCalls, 1);
    });
  });

  group('AutoStartNotifier', () {
    if (!Platform.isMacOS) {
      test('非 macOS 且非 Windows 平台保持 false 不动（真实 Platform 分发）', () async {
        if (Platform.isWindows) return;
        final n = AutoStartNotifier();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(n.state, isFalse);
        await n.toggle();
        expect(n.state, isFalse);
      });
      return;
    }

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    test('init 读 getAutoStart 返回 true', () async {
      var getCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') {
              getCalls++;
              return true;
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(getCalls, 1);
      expect(n.state, isTrue);
    });

    test('toggle false → true 调 setAutoStart(true) + state 翻转', () async {
      bool? receivedEnabled;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') return false;
            if (call.method == 'setAutoStart') {
              receivedEnabled = (call.arguments as Map)['enabled'] as bool?;
              return null;
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isFalse);
      await n.toggle();
      expect(receivedEnabled, isTrue);
      expect(n.state, isTrue);
    });

    test('native 抛错时保持当前 state', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            if (call.method == 'getAutoStart') return true;
            if (call.method == 'setAutoStart') {
              throw PlatformException(code: 'ERR');
            }
            return null;
          });
      final n = AutoStartNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(n.state, isTrue);
      await n.toggle();
      // 异常被吞，状态保持
      expect(n.state, isTrue);
    });
  });
}
