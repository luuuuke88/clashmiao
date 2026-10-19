import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final proxyDelayCacheProvider =
    StateNotifierProvider<ProxyDelayCacheNotifier, Map<String, int>>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final store = ref.watch(profileStoreProvider).valueOrNull;
      // 只关心「哪一代的哪个订阅」：订阅元数据变化（刷新、改名）不该重建 notifier。
      final active = ref.watch(
        activeProfileProvider.select((value) {
          final profile = value.valueOrNull;
          return profile == null ? null : (profile.id, profile.inc);
        }),
      );
      return ProxyDelayCacheNotifier(
        prefs: prefs,
        store: store,
        profileId: active?.$1,
        profileInc: active?.$2,
      );
    });

class ProxyDelayCacheNotifier extends StateNotifier<Map<String, int>> {
  ProxyDelayCacheNotifier({
    required SharedPreferences prefs,
    required ProfileStore? store,
    required String? profileId,
    required String? profileInc,
  }) : _store = store,
       _profileId = profileId,
       _profileInc = profileInc,
       super(_read(prefs, profileId));

  final ProfileStore? _store;
  final String? _profileId;

  /// 创建时订阅的代际；写入经 `ProfileStore.writeAux` 校验，订阅已删除或
  /// 换代后丢弃，避免旧 notifier 复活孤儿键。
  final String? _profileInc;

  static String _key(String profileId) => ProfileStore.delaysKey(profileId);

  static Map<String, int> _read(SharedPreferences prefs, String? profileId) {
    if (profileId == null || profileId.isEmpty) return const {};
    final raw = prefs.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((key, value) {
        final delay = value is int ? value : int.tryParse(value.toString());
        return MapEntry(key.toString(), delay ?? 0);
      })..removeWhere((_, delay) => delay <= 0);
    } catch (_) {
      return const {};
    }
  }

  void persistFromGroups(List<OutboundGroup> groups) {
    final profileId = _profileId;
    final store = _store;
    if (profileId == null || profileId.isEmpty || store == null) return;

    final next = Map<String, int>.from(state);
    var changed = false;
    for (final group in groups) {
      for (final item in group.items) {
        if (item.tag.isEmpty || item.delay <= 0) continue;
        if (next[item.tag] == item.delay) continue;
        next[item.tag] = item.delay;
        changed = true;
      }
    }

    if (!changed) return;
    state = Map.unmodifiable(next);
    unawaited(
      store.writeAux(
        profileId,
        _profileInc ?? '',
        _key(profileId),
        jsonEncode(next),
      ),
    );
  }
}
