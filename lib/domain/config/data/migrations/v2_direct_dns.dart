import 'dart:convert';

import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/domain/config/model/dns_defaults.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1 → v2 迁移前，直连 DNS 原值的备份键（仅当不存在时写入）。
const kMigrationBackupV1DirectDnsKey =
    'clashmiao_migration_backup_v1_direct_dns';

/// 存储 schema 1 → 2：旧版本自动写入的直连 DNS 默认值改回跟随默认值。
///
/// 直连 DNS 的默认值已从 `1.1.1.1` 改为国内解析器（[kDefaultDirectDnsAddress]）。
/// 没动过这项的用户偏好里没有这个键，直接跟随新默认；但旧版本会在用户不知情
/// 时把 `1.1.1.1` 写进去（见 [kLegacyDirectDnsDefaults]），这些用户卡在了境外
/// 解析器上。这一步把恰好等于旧默认写法的值删掉，让它跟随默认值；任何别的值
/// 都是用户自己填的，原样保留。
Migration directDnsV2Migration() => const Migration(
  toVersion: 2,
  name: 'direct_dns_default',
  run: migrateDirectDnsToV2,
);

/// v1 → v2 的具体步骤。**幂等**：在任意写入点被中断后整体重跑，结果与一次
/// 跑完一致；每个写入都检查返回值，失败即返回 `false`。
///
/// 1. 原值是旧默认写法时，先把它备份到 [kMigrationBackupV1DirectDnsKey]
///    （只在备份键不存在时写）；
/// 2. 删除直连 DNS 键。删掉之后重跑时原值已不是旧默认写法，什么都不做。
Future<bool> migrateDirectDnsToV2(SharedPreferences prefs) async {
  try {
    final raw = prefs.get(kDirectDnsAddressPrefKey);
    if (!isLegacyDirectDnsDefault(raw)) return true;
    if (!prefs.containsKey(kMigrationBackupV1DirectDnsKey)) {
      final backup = jsonEncode({kDirectDnsAddressPrefKey: raw});
      if (!await prefs.setString(kMigrationBackupV1DirectDnsKey, backup)) {
        return false;
      }
    }
    return await prefs.remove(kDirectDnsAddressPrefKey);
  } catch (e, st) {
    debugPrint('[v2_direct_dns] 迁移异常: $e\n$st');
    return false;
  }
}
