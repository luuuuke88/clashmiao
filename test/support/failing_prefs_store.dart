import 'package:flutter/services.dart';
// 测试专用：直接替换平台层存储，才能让「真实的 SharedPreferences」（先改内存缓存、
// 再写底层）在底层写入失败时露出真实行为；该包是 shared_preferences 的传递依赖。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟真实平台后端「先改自己的内存缓存、再落盘」的存储（Android 原生
/// SharedPreferences、Linux/Windows 实现都是这个顺序）：写入时先更新缓存，
/// 对 [failKeys] 里的键再让落盘失败（返回 `false` 或抛出）——此时缓存里有值、
/// 磁盘上没有，`getAll()`（包括 `reload()` 读到的）返回的是缓存。
///
/// 所有写入尝试都按顺序记录在 [attempts]（不含键前缀）。
/// 磁盘内容见 [disk]；用 [install] 以 `disk` 为初始内容再装一份，等价于新进程启动。
class FailingPrefsStore extends InMemorySharedPreferencesStore {
  FailingPrefsStore(Map<String, Object> data)
    : disk = Map.of(data),
      super.withData({
        for (final e in data.entries) '$_prefix${e.key}': e.value,
      });

  static const _prefix = 'flutter.';

  /// 已落盘的值（不含键前缀）。
  final Map<String, Object> disk;

  /// 这些键的写入会失败（缓存已改、磁盘未改）；空集合表示不失败。
  Set<String> failKeys = {};

  /// 失败的方式：`true` 抛 [PlatformException]，`false` 返回 `false`。
  bool failByThrowing = false;

  final List<String> attempts = [];

  bool _fails(String key) => failKeys.contains(key.substring(_prefix.length));

  Future<bool> _persist(String key, bool Function() apply) async {
    final bare = key.substring(_prefix.length);
    attempts.add(bare);
    if (_fails(key)) {
      if (failByThrowing) {
        throw PlatformException(code: 'disk', message: 'full');
      }
      return false;
    }
    return apply();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await super.setValue(valueType, key, value); // 缓存先改
    return _persist(key, () {
      disk[key.substring(_prefix.length)] = value;
      return true;
    });
  }

  @override
  Future<bool> remove(String key) async {
    await super.remove(key); // 缓存先改
    return _persist(key, () {
      disk.remove(key.substring(_prefix.length));
      return true;
    });
  }

  /// 安装成平台存储并返回绑定在它上面的真实 [SharedPreferences]。
  /// 再次调用（传入上一份的 `disk`）等价于一个全新的进程。
  static Future<(FailingPrefsStore, SharedPreferences)> install(
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(const {}); // 重置内部缓存单例
    final store = FailingPrefsStore(initial);
    SharedPreferencesStorePlatform.instance = store;
    return (store, await SharedPreferences.getInstance());
  }
}
