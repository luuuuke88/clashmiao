import 'dart:convert';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
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
      final store = ref.watch(profileStoreProvider).value;
      // 只关心「哪一代的哪个订阅」：订阅元数据变化（刷新、改名）不该重建 notifier。
      final active = ref.watch(
        activeProfileProvider.select((value) {
          final profile = value.value;
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
    required this._store,
    required String? profileId,
    required this._profileInc,
  }) : _profileId = profileId,
       super(_read(prefs, profileId));

  final ProfileStore? _store;
  final String? _profileId;

  /// 这个 notifier 所属的订阅 id 与代际（写入只会落到它们名下）。
  String? get profileId => _profileId;
  String? get profileInc => _profileInc;

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

  /// 每个分组的写入版本：本 notifier 每次改动该组的内存记录（[persist] /
  /// [restore] / [removeGroups]）都递增。用作「这条记录还是不是我写的」的
  /// 意图 token——回滚只撤销仍属于自己的那次写入，不覆盖之后更新的选择。
  final Map<String, int> _versions = {};
  int _clock = 0;

  /// [groupTag] 当前的写入版本（从未改动过为 0）。
  int versionOf(String groupTag) => _versions[groupTag] ?? 0;

  void _bump(Iterable<String> groupTags) {
    for (final tag in groupTags) {
      _versions[tag] = ++_clock;
    }
  }

  /// 记住 [groupTag] 这个代理组最近一次被手动选中的 [outboundTag]，
  /// 覆盖同一 group 之前的选择。
  ///
  /// 返回是否确认落盘（值本来就相同也算）；订阅已删除 / 换代、写入失败为 false。
  Future<bool> persist(String groupTag, String outboundTag) =>
      persistTracked(groupTag, outboundTag).persisted;

  /// 同 [persist]，另外同步返回这次写入后该组的版本（[versionOf]），供调用方
  /// 之后按版本条件回滚（[restore] 的 `ifVersion`）。内存在返回前就已更新。
  ({int version, Future<bool> persisted}) persistTracked(
    String groupTag,
    String outboundTag,
  ) {
    final profileId = _profileId;
    final store = _store;
    if (profileId == null || profileId.isEmpty || store == null) {
      return (version: versionOf(groupTag), persisted: Future.value(false));
    }
    if (state[groupTag] == outboundTag) {
      return (version: versionOf(groupTag), persisted: Future.value(true));
    }

    final next = {...state, groupTag: outboundTag};
    state = Map.unmodifiable(next);
    _bump([groupTag]);
    return (
      version: versionOf(groupTag),
      persisted: store.writeAux(
        profileId,
        _profileInc ?? '',
        _key(profileId),
        jsonEncode(next),
      ),
    );
  }

  /// 把 [groupTag] 的记录恢复成 [previous]（null = 原本没有记录，即删除）。
  ///
  /// 手选流程先写入新值再调用内核；内核拒绝时用它回滚，保持「失败不持久化」。
  /// 与 [persist] 同走 `ProfileStore.writeAux`：订阅已删除或换代时回滚同样被丢弃。
  ///
  /// [ifVersion]：只有该组当前版本仍等于它（即记录仍是那次写入的结果）时才
  /// 回滚；之后有更新的写入则什么都不做（内存、磁盘都不动），返回 false。
  Future<bool> restore(String groupTag, String? previous, {int? ifVersion}) {
    final profileId = _profileId;
    final store = _store;
    if (profileId == null || profileId.isEmpty) return Future.value(false);
    if (store == null) return Future.value(false);
    if (ifVersion != null && versionOf(groupTag) != ifVersion) {
      return Future.value(false);
    }
    if (state[groupTag] == previous) return Future.value(true);
    final next = {...state};
    if (previous == null) {
      next.remove(groupTag);
    } else {
      next[groupTag] = previous;
    }
    state = Map.unmodifiable(next);
    _bump([groupTag]);
    return store.writeAux(
      profileId,
      _profileInc ?? '',
      _key(profileId),
      jsonEncode(next),
    );
  }

  /// 删除这些分组的记录（迁移完成的来源，见 `planSelectionMigration`）。返回是否
  /// 确认落盘（本来就没有也算）。
  Future<bool> removeGroups(Set<String> groupTags) async {
    final profileId = _profileId;
    final store = _store;
    if (profileId == null || profileId.isEmpty) return false;
    if (store == null) return false;
    if (!groupTags.any(state.containsKey)) return true;
    final next = {...state}..removeWhere((key, _) => groupTags.contains(key));
    state = Map.unmodifiable(next);
    _bump(groupTags);
    return store.writeAux(
      profileId,
      _profileInc ?? '',
      _key(profileId),
      jsonEncode(next),
    );
  }
}
