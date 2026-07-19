import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kProxyDelayCachePrefix = 'proxy_delays_';

final proxyDelayCacheProvider =
    StateNotifierProvider<ProxyDelayCacheNotifier, Map<String, int>>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final profileId = ref.watch(activeProfileProvider).valueOrNull?.id;
      return ProxyDelayCacheNotifier(prefs: prefs, profileId: profileId);
    });

class ProxyDelayCacheNotifier extends StateNotifier<Map<String, int>> {
  ProxyDelayCacheNotifier({
    required SharedPreferences prefs,
    required String? profileId,
  }) : _prefs = prefs,
       _profileId = profileId,
       super(_read(prefs, profileId));

  final SharedPreferences _prefs;
  final String? _profileId;

  static String _key(String profileId) => '$_kProxyDelayCachePrefix$profileId';

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
    if (profileId == null || profileId.isEmpty) return;

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
    unawaited(_prefs.setString(_key(profileId), jsonEncode(next)));
  }
}
