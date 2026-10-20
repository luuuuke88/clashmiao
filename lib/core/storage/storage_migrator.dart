import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一步迁移：把偏好从 `toVersion - 1` 带到 `toVersion`。
///
/// 约定（框架依赖这些来保证「可重跑、不丢数据」）：
/// - [run] 必须**幂等**：在任意写入点被中断后整体重跑，结果与一次跑完一致；
/// - [run] 里每个写入都要检查返回值，失败就返回 `false`（或抛出），不要往下走；
/// - [run] **不要**自己写 schema 键：整步成功后由 [StorageMigrator] 统一推进；
/// - 只用原始偏好，不经任何业务 notifier。
class Migration {
  const Migration({
    required this.toVersion,
    required this.name,
    required this.run,
  });

  final int toVersion;
  final String name;
  final Future<bool> Function(SharedPreferences prefs) run;
}

enum MigrationOutcome {
  /// 已经是目标版本，什么都没做。
  upToDate,

  /// 至少跑完了一步，版本已推进。
  migrated,

  /// 某一步失败（返回 false / 抛出 / 写 schema 失败）：停在失败前的版本。
  failed,

  /// 存储版本高于本版本支持的（用户降级）：不迁移、不写任何东西。
  newerSchema,
}

class MigrationReport {
  const MigrationReport({
    required this.outcome,
    required this.fromSchema,
    required this.toSchema,
    this.failedStep,
  });

  final MigrationOutcome outcome;

  /// 迁移开始前的版本。
  final int fromSchema;

  /// 迁移结束后存储里实际的版本（失败时是最后一个成功的版本）。
  final int toSchema;

  /// 失败的那一步的 `toVersion`。
  final int? failedStep;

  bool get failed => outcome == MigrationOutcome.failed;

  @override
  String toString() =>
      'MigrationReport($outcome, $fromSchema -> $toSchema'
      '${failedStep == null ? '' : ', failedStep=$failedStep'})';
}

/// 偏好存储的版本迁移框架。
///
/// - 迁移失败**不抛出**：业务代码同时兼容新旧格式（读取容错），失败时 App 照常使用，
///   下次启动再试；
/// - 步骤失败即停，不推进 schema，也不跑后面的步骤；
/// - 存储版本高于 [targetSchema]（降级）时不迁移，让上层按只读/保守模式运行。
///
/// **失败在本进程内粘滞**：任何一次写入返回 `false` 或抛出之后，这个迁移器实例
/// 把失败的报告记在内存里（不持久化）；之后在同一进程内再调用 [run]，一律原样
/// 返回这份失败报告——不读 schema、不写任何东西、不跑任何步骤，绝不会返回
/// [MigrationOutcome.upToDate]。原因：平台后端（Android 原生 SharedPreferences、
/// Linux/Windows 的实现等）都是「先改自己的内存缓存、再落盘」，写盘失败后缓存里
/// 仍留着没落盘的值（例如 schema=1），`prefs.reload()` 也读回这份缓存，所以**不能
/// 靠重新读取来判断迁移有没有成功**。本进程里业务代码就在这份内存视图上运行
/// （迁移的数据步骤都在写 schema 之前完成，数据本身已经是新格式；读取代码同时
/// 兼容新旧格式）；下次启动是新进程，重新读磁盘、幂等重跑迁移。
///
/// 并发调用共享同一次运行。因此需要「进程内只有一个迁移器实例」才有粘滞效果，
/// 见 `prepareStorage`。
class StorageMigrator {
  StorageMigrator({required List<Migration> migrations})
    : migrations = List.unmodifiable(migrations) {
    for (var i = 0; i < migrations.length; i++) {
      if (migrations[i].toVersion != i + 1) {
        throw ArgumentError.value(
          migrations[i].toVersion,
          'migrations[$i].toVersion',
          '迁移步骤必须从 1 起连续递增，这里应为 ${i + 1}',
        );
      }
    }
  }

  final List<Migration> migrations;

  int get targetSchema => migrations.isEmpty ? 0 : migrations.last.toVersion;

  MigrationReport? _failure;
  Future<MigrationReport>? _running;

  /// 本进程内已记录的失败（没有则为 null）。
  MigrationReport? get failure => _failure;

  Future<MigrationReport> run(SharedPreferences prefs) {
    final sticky = _failure;
    if (sticky != null) return Future.value(sticky);
    final running = _running;
    if (running != null) return running;
    final future = _run(prefs).whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  Future<MigrationReport> _run(SharedPreferences prefs) async {
    final from = readStorageSchema(prefs);
    if (from > targetSchema) {
      debugPrint('[StorageMigrator] 存储版本 $from 高于当前支持的 $targetSchema，不迁移');
      return MigrationReport(
        outcome: MigrationOutcome.newerSchema,
        fromSchema: from,
        toSchema: from,
      );
    }
    var schema = from;
    for (final step in migrations) {
      if (step.toVersion <= schema) continue;
      var ok = false;
      try {
        ok = await step.run(prefs);
      } catch (e, st) {
        debugPrint(
          '[StorageMigrator] 步骤 v${step.toVersion}(${step.name}) 抛出: $e\n$st',
        );
      }
      if (ok) {
        try {
          ok = await prefs.setInt(kStorageSchemaKey, step.toVersion);
        } catch (e) {
          debugPrint('[StorageMigrator] 写 schema 抛出: $e');
          ok = false;
        }
      }
      if (!ok) {
        // 尽力让 Dart 侧缓存与存储对齐，但**正确性不依赖它**：见类注释，平台缓存
        // 可能仍留着没落盘的值。真正的保证是下面的进程内粘滞失败记录。
        await _resync(prefs);
        debugPrint(
          '[StorageMigrator] 步骤 v${step.toVersion}(${step.name}) 失败，停止；'
          '本进程内不再重试，下次启动重新迁移',
        );
        return _failure = MigrationReport(
          outcome: MigrationOutcome.failed,
          fromSchema: from,
          toSchema: schema,
          failedStep: step.toVersion,
        );
      }
      schema = step.toVersion;
    }
    return MigrationReport(
      outcome: schema == from
          ? MigrationOutcome.upToDate
          : MigrationOutcome.migrated,
      fromSchema: from,
      toSchema: schema,
    );
  }
}

Future<void> _resync(SharedPreferences prefs) async {
  try {
    await prefs.reload();
  } catch (e) {
    debugPrint('[StorageMigrator] 失败后重载偏好也失败: $e');
  }
}
