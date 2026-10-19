import 'dart:async';

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kProxyDelayCachePrefix = 'proxy_delays_';

final proxyDelayCacheProvider =
    StateNotifierProvider<ProxyDelayCacheNotifier, Map<String, CachedDelay>>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final profileId = ref.watch(activeProfileProvider).valueOrNull?.id;
      return ProxyDelayCacheNotifier(
        prefs: prefs,
        profileId: profileId,
        now: ref.read(latencyClockProvider),
      );
    });

class ProxyDelayCacheNotifier extends StateNotifier<Map<String, CachedDelay>> {
  ProxyDelayCacheNotifier({
    required SharedPreferences prefs,
    required String? profileId,
    DateTime Function()? now,
  }) : _prefs = prefs,
       _profileId = profileId,
       _now = now ?? DateTime.now,
       super(_read(prefs, profileId));

  final SharedPreferences _prefs;
  final String? _profileId;
  final DateTime Function() _now;

  static String _key(String profileId) => '$_kProxyDelayCachePrefix$profileId';

  // 值格式（旧 int / 新 {ms, measuredAt}）全部在 cached_delay.dart 里。
  static Map<String, CachedDelay> _read(
    SharedPreferences prefs,
    String? profileId,
  ) {
    if (profileId == null || profileId.isEmpty) return const {};
    return decodeDelayCache(prefs.getString(_key(profileId)));
  }

  /// 把实时分组里出现的、与缓存不同的延迟记成「刚测到」。
  void persistFromGroups(List<OutboundGroup> groups) {
    final at = _now();
    final next = Map<String, CachedDelay>.from(state);
    var changed = false;
    for (final group in groups) {
      for (final item in group.items) {
        if (item.tag.isEmpty || !isMeasurableDelay(item.delay)) continue;
        if (next[item.tag]?.ms == item.delay) continue;
        next[item.tag] = CachedDelay(item.delay, at);
        changed = true;
      }
    }
    if (changed) _commit(next);
  }

  /// 一轮测速结束时调用：这些节点在 [at] 确实被测过一次，哪怕毫秒数与缓存
  /// 里的相同（[persistFromGroups] 只在数值变化时才更新时间，同值重测会
  /// 一直显示成旧数据）。
  void recordMeasured(Map<String, int> msByTag, {DateTime? at}) {
    final stamp = at ?? _now();
    final next = Map<String, CachedDelay>.from(state);
    var changed = false;
    for (final entry in msByTag.entries) {
      if (entry.key.isEmpty || !isMeasurableDelay(entry.value)) continue;
      final value = CachedDelay(entry.value, stamp);
      if (next[entry.key] == value) continue;
      next[entry.key] = value;
      changed = true;
    }
    if (changed) _commit(next);
  }

  /// 所有写入的唯一出口：更新内存状态并落盘。
  void _commit(Map<String, CachedDelay> next) {
    final profileId = _profileId;
    if (profileId == null || profileId.isEmpty) return;
    state = Map.unmodifiable(next);
    unawaited(_prefs.setString(_key(profileId), encodeDelayCache(next)));
  }
}
