import 'dart:typed_data';

import 'package:win32_registry/win32_registry.dart';

/// Windows 开机自启动：`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
/// 写一条 `应用名 = 可执行文件路径`，再配合 Explorer 的
/// `StartupApproved\Run` 标记判断用户有没有在任务管理器「启动应用」里禁用它。
///
/// 以前这段逻辑由第三方包提供，但那个包已停更，锁死了老一代 win32 依赖链，
/// 连带 package_info_plus / share_plus / file_picker 都升不上去。行为与它保持
/// 一致，已经开启自启的老用户升级后状态不变：
/// - 写入的值就是可执行文件路径本身（不加引号、不带参数），读取时逐字比较；
/// - `StartupApproved\Run` 里同名二进制值首字节为偶数（或值不存在 / 为空）视为
///   已允许，奇数视为被用户禁用；开启时写 12 字节、首字节为 2 的「已启用」标记；
/// - 关闭时两处的同名值都删掉，不存在就跳过。
///
/// 唯一有意的差异：写入时如果 `StartupApproved\Run` 键不存在会创建它（旧实现
/// 直接打开，键缺失时开启自启会抛异常、开关点了没反应）。
class WindowsRunKeyLauncher {
  WindowsRunKeyLauncher({
    required this.appName,
    required this.appPath,
    RunKeyRegistry? registry,
  }) : _registry = registry ?? const Win32RunKeyRegistry();

  final String appName;
  final String appPath;
  final RunKeyRegistry _registry;

  static const runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const startupApprovedKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

  /// 「已启用」标记的长度与首字节，和 Explorer 自己写的格式一致。
  static const startupApprovedBytesLength = 12;
  static const startupApprovedEnabledByte = 2;

  bool isEnabled() {
    if (_registry.getString(runKeyPath, appName) != appPath) return false;
    return _isStartupApproved();
  }

  void enable() {
    _registry.setString(runKeyPath, appName, appPath);
    final marker = Uint8List(startupApprovedBytesLength)
      ..[0] = startupApprovedEnabledByte;
    _registry.setBinary(startupApprovedKeyPath, appName, marker);
  }

  void disable() {
    for (final path in const [runKeyPath, startupApprovedKeyPath]) {
      if (_registry.hasValue(path, appName)) {
        _registry.removeValue(path, appName);
      }
    }
  }

  // 首字节为奇数表示被禁用；值不存在或为空都不拦截自启。
  // 参考：HKCU\...\Explorer\StartupApproved\Run 的取值约定。
  bool _isStartupApproved() {
    final value = _registry.getBinary(startupApprovedKeyPath, appName);
    if (value == null || value.isEmpty) return true;
    return value[0].isEven;
  }
}

/// [WindowsRunKeyLauncher] 用到的最小注册表操作集合，路径都相对
/// `HKEY_CURRENT_USER`。抽出来是为了让自启逻辑能在任何宿主机上用内存实现
/// 测试——真实实现走 FFI 调 Win32 API，只能在 Windows 上跑。
abstract class RunKeyRegistry {
  /// 键或值不存在、或者值不是字符串类型时返回 null。
  String? getString(String keyPath, String name);

  /// 键或值不存在、或者值不是二进制类型时返回 null。
  Uint8List? getBinary(String keyPath, String name);

  bool hasValue(String keyPath, String name);

  /// 键不存在时创建。
  void setString(String keyPath, String name, String value);

  /// 键不存在时创建。
  void setBinary(String keyPath, String name, Uint8List value);

  void removeValue(String keyPath, String name);
}

/// [RunKeyRegistry] 的真实实现（win32_registry）。读操作用 `RegGetValue`
/// 直接按路径读，键不存在时得到 null 而不是异常，也不会顺手建键。
class Win32RunKeyRegistry implements RunKeyRegistry {
  const Win32RunKeyRegistry();

  @override
  String? getString(String keyPath, String name) =>
      CURRENT_USER.getString(name, path: keyPath);

  @override
  Uint8List? getBinary(String keyPath, String name) =>
      CURRENT_USER.getBinary(name, path: keyPath);

  @override
  bool hasValue(String keyPath, String name) =>
      CURRENT_USER.getValue(name, path: keyPath) != null;

  @override
  void setString(String keyPath, String name, String value) =>
      _write(keyPath, (key) => key.setValue(name, RegistryValue.string(value)));

  @override
  void setBinary(String keyPath, String name, Uint8List value) =>
      _write(keyPath, (key) => key.setValue(name, RegistryValue.binary(value)));

  @override
  void removeValue(String keyPath, String name) =>
      _write(keyPath, (key) => key.removeValue(name));

  void _write(String keyPath, void Function(RegistryKey key) body) {
    final key = CURRENT_USER.create(keyPath);
    try {
      body(key);
    } finally {
      key.close();
    }
  }
}
