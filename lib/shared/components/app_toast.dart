import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:gap/gap.dart';
import 'package:toastification/toastification.dart';

enum ToastType { info, success, error, warning }

/// 全局 Toast 通知
class AppToast {
  AppToast._();
  static DateTime? _lastShowAt;
  static String? _lastMessage;
  static ToastificationItem? _lastItem;

  /// 防止同一条文本在短时间内重复冒泡（避免 toast 堆叠把点击吃掉）。
  static const _dedupeWindow = Duration(milliseconds: 800);

  static ToastificationItem show({
    required BuildContext context,
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final now = DateTime.now();
    final normalized = message.trim();
    if (_lastMessage == normalized &&
        _lastShowAt != null &&
        now.difference(_lastShowAt!) <= _dedupeWindow) {
      return _lastItem ??
          toastification.showCustom(
            context: context,
            autoCloseDuration: const Duration(seconds: 0),
            alignment: Alignment.bottomCenter,
            builder: (context, holder) => const SizedBox.shrink(),
          );
    }

    _lastMessage = normalized;
    _lastShowAt = now;

    // 同时弹出的 toast 会增加 Overlay 拦截区域，直接“顶替”而不是叠加。
    toastification.dismissAll(delayForAnimation: false);

    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final (icon, color) = _iconAndColor(theme, type);

    return _lastItem = toastification.showCustom(
      context: context,
      autoCloseDuration: duration,
      alignment: Alignment.bottomCenter,
      builder: (context, holder) {
        return IgnorePointer(
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: aiUi.glassColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: aiUi.borderColor),
                boxShadow: aiUi.cardShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20),
                  const Gap(12),
                  Flexible(
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static (IconData, Color) _iconAndColor(ThemeData theme, ToastType type) {
    return switch (type) {
      ToastType.success => (
        FluentIcons.checkmark_circle_24_regular,
        Colors.green,
      ),
      ToastType.error => (FluentIcons.dismiss_circle_24_regular, Colors.red),
      ToastType.warning => (FluentIcons.warning_24_regular, Colors.orange),
      ToastType.info => (
        FluentIcons.info_24_regular,
        theme.colorScheme.primary,
      ),
    };
  }

  static ToastificationItem success(BuildContext context, String msg) =>
      show(context: context, message: msg, type: ToastType.success);

  static ToastificationItem error(BuildContext context, String msg) => show(
    context: context,
    message: msg,
    type: ToastType.error,
    duration: const Duration(seconds: 5),
  );

  static ToastificationItem info(BuildContext context, String msg) =>
      show(context: context, message: msg, type: ToastType.info);

  static ToastificationItem warning(BuildContext context, String msg) =>
      show(context: context, message: msg, type: ToastType.warning);
}
