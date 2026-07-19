import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// 平台无关的"开机自启动"读/写抽象。存在的意义是让 [AutoStartNotifier] 的
/// init/toggle 分发逻辑可以脱离真实 `dart:io Platform`（宿主机是什么系统就
/// 只能测什么系统）单独测试——通过构造函数注入一个假 backend。
abstract class AutoStartBackend {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

/// macOS：走 native MethodChannel（SMAppService 实现在 macOS 工程里）。
class _MacAutoStartBackend implements AutoStartBackend {
  const _MacAutoStartBackend(this._channel);

  final MethodChannel _channel;

  @override
  Future<bool> isEnabled() async {
    final enabled = await _channel.invokeMethod<bool>('getAutoStart');
    return enabled ?? false;
  }

  @override
  Future<void> setEnabled(bool enabled) {
    return _channel.invokeMethod('setAutoStart', {'enabled': enabled});
  }
}

/// 薄封装，把 `launch_at_startup` 包的全局单例包一层接口，方便测试注入假实现。
/// 直接测真单例不可行：它内部按*运行测试的宿主机*真实 `Platform.isXxx`
/// 分发到 Windows 注册表 / macOS LaunchAgents / Linux autostart 文件，在非
/// Windows 机器上跑测试要么崩（win32_registry 走 FFI 调 Win32 API），要么
/// 静默写脏宿主机的真实文件。
abstract class WindowsLaunchAtStartupApi {
  void setup({required String appName, required String appPath});
  Future<bool> isEnabled();
  Future<bool> enable();
  Future<bool> disable();
}

class _RealWindowsLaunchAtStartupApi implements WindowsLaunchAtStartupApi {
  const _RealWindowsLaunchAtStartupApi();

  @override
  void setup({required String appName, required String appPath}) {
    launchAtStartup.setup(appName: appName, appPath: appPath);
  }

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<bool> enable() => launchAtStartup.enable();

  @override
  Future<bool> disable() => launchAtStartup.disable();
}

/// Windows：真正的开机自启动实现，写 `HKCU\...\CurrentVersion\Run` 注册表键
/// （`launch_at_startup` 包内部实现，见其 `AppAutoLauncherImplWindows`）。
///
/// 此前的 bug：[AutoStartNotifier] 对所有非 macOS 平台的 `_init`/`toggle`
/// 直接 `if (!Platform.isMacOS) return`，短路空转。但设置页
/// （settings_page.dart:195）的开关门禁是 `Platform.isMacOS ||
/// Platform.isWindows`——Windows 用户能看到、能点这个开关，点了却完全没有
/// 任何效果，是个纯粹的假开关。这个类是 Windows 分支的真实实现。
class WindowsAutoStartBackend implements AutoStartBackend {
  WindowsAutoStartBackend({
    WindowsLaunchAtStartupApi? api,
    String appName = 'ClashMiao',
    String? appPath,
  }) : _api = api ?? const _RealWindowsLaunchAtStartupApi() {
    _api.setup(
      appName: appName,
      appPath: appPath ?? Platform.resolvedExecutable,
    );
  }

  final WindowsLaunchAtStartupApi _api;

  @override
  Future<bool> isEnabled() => _api.isEnabled();

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await _api.enable();
    } else {
      await _api.disable();
    }
  }
}

/// macOS 13+ 使用 SMAppService 实现开机启动（见 _MacAutoStartBackend）。
/// Windows 使用 launch_at_startup 包写 Registry Run 键（见
/// [WindowsAutoStartBackend]）。其余平台（Linux/mobile）不支持，backend 为
/// null，init/toggle 都是 no-op，state 恒为 false——这与之前的行为一致，
/// 且这些平台在 settings_page.dart 里本来就不会展示这个开关。
class AutoStartNotifier extends StateNotifier<bool> {
  AutoStartNotifier({AutoStartBackend? debugBackend}) : super(false) {
    _backend = debugBackend ?? _resolvePlatformBackend();
    if (_backend != null) {
      _init();
    }
  }

  static const _channel = MethodChannel('com.clashmiao/auto_start');

  late final AutoStartBackend? _backend;

  static AutoStartBackend? _resolvePlatformBackend() {
    if (Platform.isMacOS) return const _MacAutoStartBackend(_channel);
    if (Platform.isWindows) return WindowsAutoStartBackend();
    return null;
  }

  Future<void> _init() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      state = await backend.isEnabled();
    } catch (_) {
      state = false;
    }
  }

  Future<void> toggle() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final newValue = !state;
      await backend.setEnabled(newValue);
      state = newValue;
    } catch (_) {
      // native 调用失败，保持原状态
    }
  }
}

final autoStartProvider = StateNotifierProvider<AutoStartNotifier, bool>((ref) {
  return AutoStartNotifier();
});
