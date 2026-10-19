import 'dart:convert';

import 'package:clashmiao/core/latency/latency_rules.dart';

/// 缓存里的一条延迟：毫秒数 + 测量时间。
///
/// [measuredAt] 为 `null` 表示「历史值」——旧版本只存了裸 int，不知道是什么
/// 时候测的，展示层按「已过期」处理。
class CachedDelay {
  const CachedDelay(this.ms, this.measuredAt);

  final int ms;
  final DateTime? measuredAt;

  @override
  bool operator ==(Object other) =>
      other is CachedDelay && other.ms == ms && other.measuredAt == measuredAt;

  @override
  int get hashCode => Object.hash(ms, measuredAt);

  @override
  String toString() => 'CachedDelay($ms, $measuredAt)';
}

// ---------------------------------------------------------------------------
// 持久化格式（集中在这两个函数里，缓存 notifier 的读写路径只调它们）：
//   旧：{"tag": 123}                                      裸 int（或数字字符串）
//   新：{"tag": {"ms": 123, "measuredAt": 1760000000000}} measuredAt 为毫秒时间戳
// 读两种都认；写只写新格式。measuredAt 为 null 的条目不写该字段，
// 这样「历史值」重新落盘后仍是历史值。
// ---------------------------------------------------------------------------

/// 解码 SharedPreferences 里存的缓存串；任何异常都得到空表（缓存丢了只是
/// 少几个历史数字，不能让页面起不来）。
Map<String, CachedDelay> decodeDelayCache(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    final result = <String, CachedDelay>{};
    decoded.forEach((key, value) {
      final entry = _decodeEntry(value);
      if (entry != null) result[key.toString()] = entry;
    });
    return result;
  } catch (_) {
    return const {};
  }
}

CachedDelay? _decodeEntry(Object? value) {
  final int? ms;
  DateTime? measuredAt;
  if (value is Map) {
    ms = _asInt(value['ms']);
    final at = _asInt(value['measuredAt']);
    if (at != null) measuredAt = DateTime.fromMillisecondsSinceEpoch(at);
  } else {
    ms = _asInt(value);
  }
  // 旧版本把 65535 之类的「超时哨兵」也存了进来：不是真实毫秒数，丢掉。
  if (ms == null || !isMeasurableDelay(ms)) return null;
  return CachedDelay(ms, measuredAt);
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

/// 编码成要落盘的字符串（新格式）。
String encodeDelayCache(Map<String, CachedDelay> cache) {
  return jsonEncode({
    for (final entry in cache.entries)
      entry.key: {
        'ms': entry.value.ms,
        if (entry.value.measuredAt != null)
          'measuredAt': entry.value.measuredAt!.millisecondsSinceEpoch,
      },
  });
}
