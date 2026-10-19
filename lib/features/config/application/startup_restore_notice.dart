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

/// 重试启动时没完成的自动恢复：用同一个引擎再检查一次标记。
/// 做成 provider 是为了界面测试可以替换。
final startupRestoreRetryProvider =
    Provider<Future<RecoveryOutcome> Function()>(
      (ref) =>
          () async =>
              (await BackupService.engineWith(ref.read)).recoverInterrupted(),
    );

/// 这个结局需要提示用户吗。
bool needsStartupRestoreNotice(RecoveryOutcome? outcome) =>
    outcome == RecoveryOutcome.failed ||
    outcome == RecoveryOutcome.unrecoverable;
