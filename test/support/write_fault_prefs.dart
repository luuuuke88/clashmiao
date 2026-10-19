import 'package:shared_preferences/shared_preferences.dart';

/// 包一层真实 [SharedPreferences]：所有写操作（set* / remove）都可以按「操作 +
/// 键」选择性地失败。失败的样子与真实平台一致——内存缓存**已经**改掉，
/// 但返回 `false`（落盘失败）。
///
/// [failWhen] 在每次写入之后被问一次，返回 true 就让这次写入「失败」。
/// [log] 记录每次写入（操作:键），供测试断言写入顺序与次数。
class WriteFaultPrefs implements SharedPreferences {
  WriteFaultPrefs(this.inner);

  final SharedPreferences inner;

  /// `(op, key)`：op 为 `set` 或 `remove`。
  bool Function(String op, String key)? failWhen;

  /// 写入真正落到缓存**之前**被调用并等待。测试用它把某次写入「卡住」——
  /// 等价于进程恰好在这一刻被杀（卡住的 Future 永远不返回）。
  Future<void> Function(String op, String key)? beforeWrite;

  final List<String> log = [];

  Future<bool> _write(
    String op,
    String key,
    Future<bool> Function() run,
  ) async {
    log.add('$op:$key');
    final gate = beforeWrite;
    if (gate != null) await gate(op, key);
    final ok = await run();
    final fail = failWhen?.call(op, key) ?? false;
    return fail ? false : ok;
  }

  @override
  Future<bool> setString(String key, String value) =>
      _write('set', key, () => inner.setString(key, value));

  @override
  Future<bool> setBool(String key, bool value) =>
      _write('set', key, () => inner.setBool(key, value));

  @override
  Future<bool> setInt(String key, int value) =>
      _write('set', key, () => inner.setInt(key, value));

  @override
  Future<bool> setDouble(String key, double value) =>
      _write('set', key, () => inner.setDouble(key, value));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write('set', key, () => inner.setStringList(key, value));

  @override
  Future<bool> remove(String key) =>
      _write('remove', key, () => inner.remove(key));

  @override
  Object? get(String key) => inner.get(key);

  @override
  String? getString(String key) => inner.getString(key);

  @override
  bool? getBool(String key) => inner.getBool(key);

  @override
  int? getInt(String key) => inner.getInt(key);

  @override
  double? getDouble(String key) => inner.getDouble(key);

  @override
  List<String>? getStringList(String key) => inner.getStringList(key);

  @override
  Set<String> getKeys() => inner.getKeys();

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
