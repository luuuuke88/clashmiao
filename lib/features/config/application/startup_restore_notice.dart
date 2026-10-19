import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/data/backup_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 本次启动时「恢复标记检查」的结果，由 `main()` 在启动屏障之后写入。
///
/// 只有 [RecoveryOutcome.failed]（自动回滚没完成，标记保留）与
/// [RecoveryOutcome.unrecoverable]（快照丢了 / 坏了，无法回滚）需要告诉用户；
/// 其余（没有标记、成功回滚）界面不打扰。
final startupRestoreRecoveryProvider = StateProvider<RecoveryOutcome?>(
  (ref) => null,
);

/// 恢复引擎（默认按真实路径构造）。做成 provider 是为了界面与集成测试可以替换。
final backupEngineProvider = FutureProvider<BackupEngine>(
  (ref) => BackupService.engineWith(ref.read),
);

/// 重试启动时没完成的自动恢复：走 [RestoreRefresher.recoverInterrupted]，
/// 与导入同一套协调（互斥内暂停定时刷新、恢复、成败都刷新、最后解除暂停）。
final startupRestoreRetryProvider =
    Provider<Future<RecoveryOutcome> Function()>((ref) {
      return () async {
        final engine = await ref.read(backupEngineProvider.future);
        final container = ref.container;
        return RestoreRefresher(
          container: container,
          extraInvalidations: ref.read(restoreExtraInvalidationsProvider),
        ).recoverInterrupted(engine);
      };
    });

/// 这个结局需要提示用户吗。
bool needsStartupRestoreNotice(RecoveryOutcome? outcome) =>
    outcome == RecoveryOutcome.failed ||
    outcome == RecoveryOutcome.unrecoverable;
