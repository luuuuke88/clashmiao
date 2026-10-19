import 'package:shared_preferences/shared_preferences.dart';

/// 模拟「写到第 N 次就中断」的偏好：前 [allowedWrites] 次写入（set / remove）
/// 正常落盘，之后的写入一律返回 `false` 且**不生效**——等价于进程在那一刻被杀
/// （之后什么都没落盘），也等价于磁盘写失败（迁移代码必须停手）。
///
/// [allowedWrites] 为 null 表示不限制。读取永远透传。
class CrashablePrefs implements SharedPreferences {
  CrashablePrefs(this.inner, {this.allowedWrites});

  final SharedPreferences inner;
  int? allowedWrites;

  /// 已尝试的写入（含被拒的），按顺序记录键。
  final List<String> attempts = [];

  /// 实际生效的写入次数。
  int applied = 0;

  bool _admit(String key) {
    attempts.add(key);
    final left = allowedWrites;
    if (left != null && applied >= left) return false;
    applied++;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async =>
      _admit(key) ? inner.setString(key, value) : false;

  @override
  Future<bool> setInt(String key, int value) async =>
      _admit(key) ? inner.setInt(key, value) : false;

  @override
  Future<bool> setBool(String key, bool value) async =>
      _admit(key) ? inner.setBool(key, value) : false;

  @override
  Future<bool> setDouble(String key, double value) async =>
      _admit(key) ? inner.setDouble(key, value) : false;

  @override
  Future<bool> setStringList(String key, List<String> value) async =>
      _admit(key) ? inner.setStringList(key, value) : false;

  @override
  Future<bool> remove(String key) async =>
      _admit(key) ? inner.remove(key) : false;

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
  // ignore: deprecated_member_use
  Future<bool> commit() => inner.commit();

  @override
  Future<bool> clear() => inner.clear();

  @override
  Future<void> reload() => inner.reload();
}
