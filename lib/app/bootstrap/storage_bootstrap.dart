import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/domain/profile/data/migrations/v1_profiles.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动时的恢复标记检查：发现上次备份恢复中途被中断（标记键还在）时，
/// 用恢复前快照自动回到恢复前状态。**子项目 C1-3 在此接入实现**，
/// 之前（[prepareStorage] 的 `checkRestoreMarker` 为空）什么都不做。
typedef RestoreMarkerCheck = Future<void> Function(SharedPreferences prefs);

/// 本版本全部存储迁移，按版本递增排列。新增迁移只在这里追加。
List<Migration> storageMigrations() => [profilesV1Migration()];

/// 启动屏障：在**任何**业务 provider 读取偏好、向原生推送配置、启动后台任务之前
/// 调用并 `await`。
///
/// 顺序固定：①恢复标记检查（C1-3 钩子）→ ②版本迁移。迁移只用原始偏好，
/// 不经业务 notifier。两步都不会向外抛：迁移失败时业务代码兼容新旧两种格式，
/// 照常启动，下次启动再试。
Future<MigrationReport> prepareStorage(
  SharedPreferences prefs, {
  RestoreMarkerCheck? checkRestoreMarker,
  StorageMigrator? migrator,
}) async {
  if (checkRestoreMarker != null) {
    try {
      await checkRestoreMarker(prefs);
    } catch (e, st) {
      debugPrint('[storage] 恢复标记检查失败，继续启动: $e\n$st');
    }
  }
  final report =
      await (migrator ?? StorageMigrator(migrations: storageMigrations())).run(
        prefs,
      );
  debugPrint('[storage] $report');
  return report;
}
