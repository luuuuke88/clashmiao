import 'dart:async';

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

final proxyDelayCacheProvider =
    StateNotifierProvider<ProxyDelayCacheNotifier, Map<String, CachedDelay>>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final store = ref.watch(profileStoreProvider).value;
      // 只关心「哪一代的哪个订阅」：订阅元数据变化（刷新、改名）不该重建 notifier。
      final active = ref.watch(
        activeProfileProvider.select((value) {
          final profile = value.value;
          return profile == null ? null : (profile.id, profile.inc);
        }),
      );
      return ProxyDelayCacheNotifier(
        prefs: prefs,
        store: store,
        profileId: active?.$1,
        profileInc: active?.$2,
        now: ref.read(latencyClockProvider),
      );
    });

class ProxyDelayCacheNotifier extends StateNotifier<Map<String, CachedDelay>> {
  ProxyDelayCacheNotifier({
    required SharedPreferences prefs,
    required this._store,
    required String? profileId,
    required this._profileInc,
    DateTime Function()? now,
  }) : _profileId = profileId,
       _now = now ?? DateTime.now,
       super(_read(prefs, profileId));

  final ProfileStore? _store;
  final String? _profileId;
  final DateTime Function() _now;

  /// 创建时订阅的代际；写入经 `ProfileStore.writeAux` 校验，订阅已删除或
  /// 换代后丢弃，避免旧 notifier 复活孤儿键。
  final String? _profileInc;

  static String _key(String profileId) => ProfileStore.delaysKey(profileId);

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
    if (_profileId == null || _profileId.isEmpty || _store == null) return;
    final at = _now();
    final next = Map<String, CachedDelay>.from(state);
    var changed = false;
    for (final group in groups) {
      for (final item in group.items) {
        if (item.tag.isEmpty || !isMeasurableDelay(item.delay)) continue;
        // 失败记录的 ms 不会等于有效延迟：节点又测通了，成功值覆盖失败。
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

  /// 一轮测速结束时调用：这些节点在 [at] 测了没通（失败 / 超时）。把它们记成
  /// 失败并落盘，缓存里更早的成功值就不会再冒出来——不论是本次会话里的显示，
  /// 还是重启之后。之后节点又测通，成功值（[recordMeasured] /
  /// [persistFromGroups]）会覆盖它。
  void recordFailed(Iterable<String> tags, {DateTime? at}) {
    final stamp = at ?? _now();
    final next = Map<String, CachedDelay>.from(state);
    var changed = false;
    for (final tag in tags) {
      if (tag.isEmpty) continue;
      final value = CachedDelay.failed(stamp);
      if (next[tag] == value) continue;
      next[tag] = value;
      changed = true;
    }
    if (changed) _commit(next);
  }

  /// 所有写入的唯一出口：更新内存状态并落盘。
  void _commit(Map<String, CachedDelay> next) {
    final profileId = _profileId;
    if (profileId == null || profileId.isEmpty) return;
    state = Map.unmodifiable(next);
    final store = _store;
    if (store == null) return;
    unawaited(
      store.writeAux(
        profileId,
        _profileInc ?? '',
        _key(profileId),
        encodeDelayCache(next),
      ),
    );
  }
}
