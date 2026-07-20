import 'dart:convert';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kProxySelectionPrefix = 'proxy_selection_';

/// sing-box 的 selector outbound 只在运行中的 Box 实例内存里记住"当前选中项"，
/// 每次 reconnect/restart 都会用 runtime-config.json 里的静态 `default` 重新起
/// 一个全新实例——不持久化 + 主动重放的话，用户手选的节点在下一次重连后会
/// 静默回退到 config 声明的默认值。这里按 profileId 分区记住每个 group 最近
/// 一次的手选结果，供 [ConnectionController] 在每次真正进入 BoxStarted 后重放。
final proxySelectionStoreProvider =
    StateNotifierProvider<ProxySelectionStoreNotifier, Map<String, String>>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final profileId = ref.watch(activeProfileProvider).valueOrNull?.id;
      return ProxySelectionStoreNotifier(prefs: prefs, profileId: profileId);
    });

class ProxySelectionStoreNotifier extends StateNotifier<Map<String, String>> {
  ProxySelectionStoreNotifier({
    required SharedPreferences prefs,
    required String? profileId,
  }) : _prefs = prefs,
       _profileId = profileId,
       super(_read(prefs, profileId));

  final SharedPreferences _prefs;
  final String? _profileId;

  static String _key(String profileId) => '$_kProxySelectionPrefix$profileId';

  static Map<String, String> _read(SharedPreferences prefs, String? profileId) {
    if (profileId == null || profileId.isEmpty) return const {};
    final raw = prefs.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return const {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  /// 记住 [groupTag] 这个代理组最近一次被手动选中的 [outboundTag]，
  /// 覆盖同一 group 之前的选择。
  Future<void> persist(String groupTag, String outboundTag) async {
    final profileId = _profileId;
    if (profileId == null || profileId.isEmpty) return;
    if (state[groupTag] == outboundTag) return;

    final next = {...state, groupTag: outboundTag};
    state = Map.unmodifiable(next);
    await _prefs.setString(_key(profileId), jsonEncode(next));
  }
}
