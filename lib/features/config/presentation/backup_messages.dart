import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/data/backup_service.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';

/// 备份导入的用户可见文案：确认对话框、结果报告、失败原因。
/// 全部走 slang，纯函数，便于单测。
class BackupMessages {
  const BackupMessages._();

  /// 确认对话框正文：说明替换语义，并明确列出「本机不在备份中的订阅会被移除」。
  static String confirm(Translations t, PreparedImport prepared) {
    final b = t.settings.backup;
    final lines = [b.importConfirmMsg];
    if (prepared.willRemove.isNotEmpty) {
      lines.add(b.importRemovesMsg(count: prepared.willRemove.length));
    }
    return lines.join('\n\n');
  }

  /// 导入完成后的 [RestoreReport] 摘要。只有有话可说的部分才出现。
  static String report(Translations t, RestoreReport report) {
    final b = t.settings.backup;
    return [
      b.reportImported(
        profiles: report.profilesImported,
        settings: report.prefsImported,
      ),
      if (report.profilesDropped > 0)
        b.reportDropped(count: report.profilesDropped),
      if (report.prefsSkipped > 0)
        b.reportSettingsSkipped(count: report.prefsSkipped),
      if (report.warpDisabled) b.reportWarpOff,
      if (report.refreshQueued > 0)
        b.reportBackfill(count: report.refreshQueued),
    ].join('\n');
  }

  /// 导入失败的原因说明。
  static String error(Translations t, Object error) {
    final b = t.settings.backup;
    if (error is BackupFormatException) {
      return switch (error.kind) {
        BackupErrorKind.invalidFile => b.errInvalidFile,
        BackupErrorKind.unsupportedVersion => b.errUnsupportedVersion,
        BackupErrorKind.newerSchema => b.errNewerSchema,
        BackupErrorKind.noUsableProfiles => b.errNoUsableProfiles,
      };
    }
    if (error is RestoreFailure) {
      return switch (error.kind) {
        RestoreFailureKind.readOnly => t.failure.profiles.readOnlyUpgrade,
        RestoreFailureKind.snapshotFailed => b.errSnapshotFailed,
        RestoreFailureKind.unresolvedPrevious => b.errUnresolvedPrevious,
        RestoreFailureKind.rolledBack => b.errRolledBack,
        RestoreFailureKind.notRolledBack => b.errNotRolledBack(
          path: error.snapshotPath ?? '',
        ),
      };
    }
    if (error is StoreReadOnlyException) {
      return t.failure.profiles.readOnlyUpgrade;
    }
    return b.errFailed;
  }
}
