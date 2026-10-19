import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/config/application/startup_restore_notice.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/blocking_alert_dialog.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 启动时上次备份恢复被中断、而自动回滚没成功时的提示（首帧之后由
/// `ShellPage` 调用）。
///
/// - [RecoveryOutcome.unrecoverable]：快照丢了或坏了，无法回滚——只能告诉用户去检查
///   订阅和设置，没有可重试的动作，所以只给一个关闭按钮；
/// - [RecoveryOutcome.failed]：标记还保留着，提供「重试」。重试成功就刷新界面并
///   提示；再次失败则回到这个对话框，直到用户关闭。
Future<void> showRestoreRecoveryNotice(
  BuildContext context,
  WidgetRef ref,
) async {
  while (true) {
    if (!context.mounted) return;
    final outcome = ref.read(startupRestoreRecoveryProvider);
    if (!needsStartupRestoreNotice(outcome)) return;
    final b = ref.read(translationsProvider).settings.backup;

    if (outcome == RecoveryOutcome.unrecoverable) {
      await showBlockingAlert(
        context,
        title: b.recoveryUnrecoverableTitle,
        message: b.recoveryUnrecoverableMsg,
        confirmLabel: b.recoveryClose,
        icon: Icons.warning_amber_rounded,
      );
      // 已经告知，不再重复提示（无可重试的动作）。
      ref.read(startupRestoreRecoveryProvider.notifier).state = null;
      return;
    }

    if (!context.mounted) return;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RetryDialog(
        title: b.recoveryFailedTitle,
        message: b.recoveryFailedMsg,
        retryLabel: b.recoveryRetry,
        closeLabel: b.recoveryClose,
      ),
    );
    if (retry != true) return; // 用户选择关闭：标记保留，下次启动 / 下次导入前还会再试。

    final next = await ref.read(startupRestoreRetryProvider)();
    if (next == RecoveryOutcome.busy) return;
    ref.read(startupRestoreRecoveryProvider.notifier).state = next;
    if (next == RecoveryOutcome.recovered || next == RecoveryOutcome.none) {
      // 界面刷新已在重试的协调流程里完成（成败都刷新）。
      ref.read(startupRestoreRecoveryProvider.notifier).state = null;
      if (context.mounted) AppToast.success(context, b.recoveryRetried);
      return;
    }
    // 仍然失败 / 无法回滚：回到循环顶部，按新的结局再提示一次。
  }
}

class _RetryDialog extends StatelessWidget {
  const _RetryDialog({
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.closeLabel,
  });

  final String title;
  final String message;
  final String retryLabel;
  final String closeLabel;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const padding = EdgeInsets.symmetric(vertical: 12);
    return AlertDialog(
      icon: Icon(
        Icons.warning_amber_rounded,
        size: 48,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('restoreRecoveryClose'),
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(padding: padding, shape: shape),
                child: Text(closeLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                key: const Key('restoreRecoveryRetry'),
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  padding: padding,
                  shape: shape,
                  elevation: 0,
                ),
                child: Text(retryLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
