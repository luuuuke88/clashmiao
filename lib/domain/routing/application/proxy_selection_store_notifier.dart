import 'dart:convert';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// sing-box 的 selector outbound 只在运行中的 Box 实例内存里记住"当前选中项"，
/// 每次 reconnect/restart 都会用 runtime-config.json 里的静态 `default` 重新起
/// 一个全新实例——不持久化 + 主动重放的话，用户手选的节点在下一次重连后会
/// 静默回退到 config 声明的默认值。这里按 profileId 分区记住每个 group 最近
/// 一次的手选结果，供 `ConnectionController` 在每次真正进入 BoxStarted 后重放。
final proxySelectionStoreProvider =
    StateNotifierProvider<ProxySelectionStoreNotifier, Map<String, String>>((
      ref,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      final store = ref.watch(profileStoreProvider).valueOrNull;
      // 只关心「哪一代的哪个订阅」：订阅元数据变化（刷新、改名）不该重建 notifier。
      final active = ref.watch(
        activeProfileProvider.select((value) {
          final profile = value.valueOrNull;
          return profile == null ? null : (profile.id, profile.inc);
        }),
      );
      return ProxySelectionStoreNotifier(
        prefs: prefs,
        store: store,
        profileId: active?.$1,
        profileInc: active?.$2,
      );
    });

class ProxySelectionStoreNotifier extends StateNotifier<Map<String, String>> {
  ProxySelectionStoreNotifier({
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

  /// 创建时订阅的代际。写入经 `ProfileStore.writeAux` 校验：订阅已删除或
  /// 同 id 换代（删除后恢复）后，旧 notifier 的写入会被丢弃，不会复活孤儿键。
  final String? _profileInc;

  static String _key(String profileId) => ProfileStore.selectionKey(profileId);

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
    final store = _store;
    if (profileId == null || profileId.isEmpty) return;
    if (store == null) return;
    if (state[groupTag] == outboundTag) return;

    final next = {...state, groupTag: outboundTag};
    state = Map.unmodifiable(next);
    await store.writeAux(
      profileId,
      _profileInc ?? '',
      _key(profileId),
      jsonEncode(next),
    );
  }

  /// 把 [groupTag] 的记录恢复成 [previous]（null = 原本没有记录，即删除）。
  ///
  /// 手选流程先写入新值再调用内核；内核拒绝时用它回滚，保持「失败不持久化」。
  /// 与 [persist] 同走 `ProfileStore.writeAux`：订阅已删除或换代时回滚同样被丢弃。
  Future<void> restore(String groupTag, String? previous) async {
    final profileId = _profileId;
    final store = _store;
    if (profileId == null || profileId.isEmpty) return;
    if (store == null) return;
    if (state[groupTag] == previous) return;
    final next = {...state};
    if (previous == null) {
      next.remove(groupTag);
    } else {
      next[groupTag] = previous;
    }
    state = Map.unmodifiable(next);
    await store.writeAux(
      profileId,
      _profileInc ?? '',
      _key(profileId),
      jsonEncode(next),
    );
  }
}
