import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';

/// 阻断式错误/重要提示弹窗：必须点击确认按钮才能关闭
/// （`barrierDismissible: false`，点遮罩不会关闭）。
///
/// 用于"用户必须看到并确认"的严重场景（例如核心服务启动失败），跟会
/// 自动消失、可能被用户划走而错过的 `AppToast.error`（见
/// `shared/components/app_toast.dart`）相对——那类 toast 没有标题、
/// 定时自动消失，重要错误信息可能根本没被用户看到就没了。
///
/// 视觉上复用项目里其它对话框共享组件（`showConfirmationDialog`，见
/// `shared/components/confirmation_dialogs.dart`）的规范：标题
/// 18/w800/-0.5，正文 14/`aiUi.secondaryTextColor`，按钮圆角12、
/// vertical padding 12；区别只在于这里只有一个确认按钮，且不可通过
/// 点遮罩关闭。
///
/// 用法：
/// ```dart
/// await showBlockingAlert(
///   context,
///   title: '连接失败',
///   message: '核心服务未能启动，请重试。',
/// );
/// ```
Future<void> showBlockingAlert(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  IconData? icon,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final localizations = MaterialLocalizations.of(context);

      return AlertDialog(
        icon: icon == null
            ? null
            : Icon(icon, size: 48, color: Theme.of(context).colorScheme.error),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(confirmLabel ?? localizations.okButtonLabel),
            ),
          ),
        ],
      );
    },
  );
}
