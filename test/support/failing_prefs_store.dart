import 'package:flutter/services.dart';
// 测试专用：直接替换平台层存储，才能让「真实的 SharedPreferences」（先改内存缓存、
// 再写底层）在底层写入失败时露出真实行为；该包是 shared_preferences 的传递依赖。
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可控失败的平台存储：对指定键的写入返回 `false` 或抛出，其余照常。
/// 所有写入尝试都会按顺序记录在 [attempts]（不含键前缀）。
class FailingPrefsStore extends InMemorySharedPreferencesStore {
  FailingPrefsStore(Map<String, Object> data)
    : super.withData({
        for (final e in data.entries) '$_prefix${e.key}': e.value,
      });

  static const _prefix = 'flutter.';

  /// 这些键的写入会失败；空集合表示不失败。
  Set<String> failKeys = {};

  /// 失败的方式：`true` 抛 [PlatformException]，`false` 返回 `false`。
  bool failByThrowing = false;

  final List<String> attempts = [];

  /// 已落盘的值（不含键前缀）。
  Future<Map<String, Object>> persisted() async => {
    for (final e in (await getAll()).entries)
      e.key.substring(_prefix.length): e.value,
  };

  bool _fails(String key) => failKeys.contains(key.substring(_prefix.length));

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    attempts.add(key.substring(_prefix.length));
    if (_fails(key)) {
      if (failByThrowing) {
        throw PlatformException(code: 'disk', message: 'full');
      }
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    attempts.add(key.substring(_prefix.length));
    if (_fails(key)) {
      if (failByThrowing) {
        throw PlatformException(code: 'disk', message: 'full');
      }
      return false;
    }
    return super.remove(key);
  }

  /// 安装成平台存储并返回绑定在它上面的真实 [SharedPreferences]。
  static Future<(FailingPrefsStore, SharedPreferences)> install(
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(const {}); // 重置内部缓存单例
    final store = FailingPrefsStore(initial);
    SharedPreferencesStorePlatform.instance = store;
    return (store, await SharedPreferences.getInstance());
  }
}
