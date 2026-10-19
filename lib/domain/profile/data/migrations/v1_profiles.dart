import 'dart:convert';

import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v0 → v1 迁移前，订阅列表与激活键原值的备份键（仅当不存在时写入）。
const kMigrationBackupV0Key = 'clashmiao_migration_backup_v0';

/// 存储 schema 0 → 1：订阅数据的规整。
///
/// [incGenerator] 只用于测试注入确定性的值；默认与 `ProfileStore` 生成 inc 的方式一致。
Migration profilesV1Migration({String Function()? incGenerator}) => Migration(
  toVersion: 1,
  name: 'profiles',
  run: (prefs) => migrateProfilesToV1(prefs, incGenerator: incGenerator),
);

/// v0 → v1 的具体步骤。**每一步幂等**，可在任意写入点被中断后整体重跑；
/// 每个写入都检查返回值，失败即返回 `false`（调用方据此不推进 schema）。
///
/// 顺序（顺序本身是正确性的一部分）：
/// 0. 把订阅列表与激活键的原值备份到 [kMigrationBackupV0Key]（只在它不存在时写）；
/// 1. 算出激活 id 并**先写激活键**——此时订阅 JSON 里的 `active` 标记还在，
///    即使在这之后被中断，重跑也会得到同一个结果；
/// 2. 重写订阅 JSON：去掉 `active`，补 `rev`（已有保留）与 `inc`（已有保留）；
/// 3. 删除不属于任何订阅的 `proxy_selection_*` / `proxy_delays_*`。
///
/// 订阅外层 JSON 无法解析（或不是数组、或存了错误类型）时跳过 1–3：
/// 此时无法判断哪些数据有效，宁可不动，由 `ProfileStore` 的容错读取兜底。
/// 看不懂的单个条目原样保留（`ProfileStore` 读取时会把它隔离，不会丢）。
Future<bool> migrateProfilesToV1(
  SharedPreferences prefs, {
  String Function()? incGenerator,
}) async {
  final newInc = incGenerator ?? ProfileStore.randomInc;
  try {
    final rawProfiles = prefs.get(ProfileStore.profilesKey);
    final rawActive = prefs.get(ProfileStore.activeProfileKey);

    // 0. 备份。两个键都没有就没有可保护的东西，不造多余的键。
    if (!prefs.containsKey(kMigrationBackupV0Key) &&
        (rawProfiles != null || rawActive != null)) {
      final backup = jsonEncode({
        ProfileStore.profilesKey: rawProfiles is String ? rawProfiles : null,
        ProfileStore.activeProfileKey: rawActive is String ? rawActive : null,
      });
      if (!await prefs.setString(kMigrationBackupV0Key, backup)) return false;
    }

    // 订阅外层读不懂：跳过订阅步骤。
    final List<Object?> items;
    if (rawProfiles == null) {
      items = const [];
    } else {
      final decoded = rawProfiles is String ? _tryDecode(rawProfiles) : null;
      if (decoded is! List) {
        debugPrint('[v1_profiles] 订阅列表无法解析，跳过订阅相关迁移步骤');
        return true;
      }
      items = decoded;
    }

    final entries = _classify(items);
    final validIds = [
      for (final e in entries)
        if (e.valid) e.id!,
    ];

    // 1. 激活 id，先写。
    final storedActive = rawActive is String ? rawActive : null;
    String? activeId;
    if (storedActive != null && validIds.contains(storedActive)) {
      activeId = storedActive;
    } else {
      activeId = entries
          .where((e) => e.valid && e.flaggedActive)
          .firstOrNull
          ?.id;
      activeId ??= validIds.firstOrNull;
    }
    if (activeId == null) {
      if (prefs.containsKey(ProfileStore.activeProfileKey) &&
          !await prefs.remove(ProfileStore.activeProfileKey)) {
        return false;
      }
    } else if (storedActive != activeId) {
      if (!await prefs.setString(ProfileStore.activeProfileKey, activeId)) {
        return false;
      }
    }

    // 2. 重写订阅 JSON（没有变化就不写）。
    if (rawProfiles != null) {
      final rewritten = jsonEncode([
        for (final e in entries)
          e.valid ? _upgrade(e.raw!, newInc) : e.original,
      ]);
      if (rewritten != rawProfiles &&
          !await prefs.setString(ProfileStore.profilesKey, rewritten)) {
        return false;
      }
    }

    // 3. 孤儿键。读不懂的条目只要能看出 id，它名下的键就保守保留。
    final keepIds = {
      for (final e in entries)
        if (e.id != null) e.id!,
    };
    for (final key in prefs.getKeys().toList()) {
      final suffix = _auxSuffix(key);
      if (suffix == null || keepIds.contains(suffix)) continue;
      if (!await prefs.remove(key)) return false;
    }
    return true;
  } catch (e, st) {
    debugPrint('[v1_profiles] 迁移异常: $e\n$st');
    return false;
  }
}

Object? _tryDecode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

String? _auxSuffix(String key) {
  for (final prefix in const ['proxy_selection_', 'proxy_delays_']) {
    if (key.startsWith(prefix)) return key.substring(prefix.length);
  }
  return null;
}

class _Entry {
  _Entry(
    this.original, {
    this.raw,
    this.id,
    this.valid = false,
    this.flaggedActive = false,
  });

  /// 条目原样（读不懂的条目写回时就是它）。
  final Object? original;

  /// 合法条目的 JSON 对象。
  final Map<String, dynamic>? raw;

  /// 能看出的 id（即使条目本身读不懂）。
  final String? id;

  final bool valid;
  final bool flaggedActive;
}

/// 按 `ProfileStore` 读取时同样的标准判定每个条目是否合法：能解析、id 合法、不重复。
List<_Entry> _classify(List<Object?> items) {
  final seen = <String>{};
  final out = <_Entry>[];
  for (final item in items) {
    final rawId = item is Map ? item['id'] : null;
    final seenId = rawId is String ? rawId : null;
    var valid = false;
    if (item is Map<String, dynamic>) {
      try {
        final entity = ProfileEntity.fromJson(item);
        valid = ProfileStore.isValidId(entity.id) && seen.add(entity.id);
      } catch (_) {
        valid = false;
      }
    }
    out.add(
      valid
          ? _Entry(
              item,
              raw: item as Map<String, dynamic>,
              id: seenId,
              valid: true,
              flaggedActive: item['active'] == true,
            )
          : _Entry(item, id: seenId),
    );
  }
  return out;
}

/// v0 条目 → v1 条目：去掉 `active`，补 `rev`、`inc`；其余字段（含未知字段）原样保留。
Map<String, dynamic> _upgrade(
  Map<String, dynamic> raw,
  String Function() newInc,
) {
  final out = Map<String, dynamic>.of(raw)..remove('active');
  final rev = out['rev'];
  if (rev is! int || rev < 1) out['rev'] = 1;
  final inc = out['inc'];
  if (inc is! String || inc.isEmpty) out['inc'] = newInc();
  return out;
}
