import 'package:shared_preferences/shared_preferences.dart';

/// 包一层真实 [SharedPreferences]，让指定键的 `setString` 按真实平台失败时的
/// 样子表现：内存缓存已经被改掉，但返回 `false`（落盘失败）。
///
/// [failWrites] 为 true 时匹配 [failKeys]（空集合表示所有键）的写入都失败；
/// [failuresLeft] 大于 0 时只让接下来的 N 次匹配写入失败，之后恢复正常。
class FlakyPrefs implements SharedPreferences {
  FlakyPrefs(this.inner);

  final SharedPreferences inner;

  /// 只对这些键失败；空表示所有键。
  Set<String> failKeys = {};

  /// 接下来还要失败几次；-1 表示一直失败。
  int failuresLeft = 0;

  /// 每次 `setString` 在「内存缓存已更新」之后、返回结果之前调用并等待。
  ///
  /// 真实平台就是这个顺序：先改缓存，磁盘结果稍后才回来。测试用它卡住写入、
  /// 在这段窗口里做同步读取，再决定放行为成功还是失败。
  Future<void> Function(String key)? afterWrite;

  /// 已记录的 setString 调用（键）。
  final List<String> setStringCalls = [];

  bool _shouldFail(String key) {
    if (failuresLeft == 0) return false;
    if (failKeys.isNotEmpty && !failKeys.contains(key)) return false;
    if (failuresLeft > 0) failuresLeft--;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    setStringCalls.add(key);
    final ok = await inner.setString(key, value);
    final hook = afterWrite;
    if (hook != null) await hook(key);
    return _shouldFail(key) ? false : ok;
  }

  @override
  Future<bool> remove(String key) async {
    final ok = await inner.remove(key);
    return _shouldFail(key) ? false : ok;
  }

  @override
  String? getString(String key) => inner.getString(key);

  @override
  Set<String> getKeys() => inner.getKeys();

  @override
  Object? get(String key) => inner.get(key);

  @override
  bool? getBool(String key) => inner.getBool(key);

  @override
  int? getInt(String key) => inner.getInt(key);

  @override
  double? getDouble(String key) => inner.getDouble(key);

  @override
  List<String>? getStringList(String key) => inner.getStringList(key);

  @override
  bool containsKey(String key) => inner.containsKey(key);

  @override
  Future<bool> setBool(String key, bool value) => inner.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) => inner.setInt(key, value);

  @override
  Future<bool> setDouble(String key, double value) =>
      inner.setDouble(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      inner.setStringList(key, value);

  @override
  // ignore: deprecated_member_use
  Future<bool> commit() => inner.commit();

  @override
  Future<bool> clear() => inner.clear();

  @override
  Future<void> reload() => inner.reload();
}
