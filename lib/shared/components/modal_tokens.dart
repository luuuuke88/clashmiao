import 'package:flutter/material.dart';

/// 底部弹层与对话框共用的外观 token：**圆角**与**遮罩**各只有一个值。
///
/// 以前快速设置圆角 24 / 毛玻璃弹层 32，遮罩分别是 40% 黑 / 透明 / Material 默认的
/// 54% 黑，同一个 App 里的弹层各是各的样子。现在：
/// - 圆角 [radius]（顶部圆角用于底部弹层，四角用于对话框）；
/// - 遮罩 [scrim]：40% 黑，明暗主题同一个值。
///
/// 用法：[apply] 套在 `MaterialApp` 的 `theme` / `darkTheme` 上，所有
/// `showModalBottomSheet` / `showDialog` 自动取用（调用点**不要**再写 `barrierColor`
/// 与圆角字面量，由架构测试守着）；自己画表面的弹层（`AiUiModalWrapper`、快速设置）
/// 直接用 [topRadius]。
abstract final class ModalTokens {
  static const double radius = 28;

  /// 底部弹层的顶部圆角。
  static const BorderRadius topRadius = BorderRadius.vertical(
    top: Radius.circular(radius),
  );

  /// 对话框的四角圆角。
  static const BorderRadius dialogRadius = BorderRadius.all(
    Radius.circular(radius),
  );

  /// 遮罩：40% 黑。
  static const Color scrim = Color(0x66000000);

  /// 把弹层 token 写进主题。
  static ThemeData apply(ThemeData theme) => theme.copyWith(
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
      modalBarrierColor: scrim,
      shape: const RoundedRectangleBorder(borderRadius: topRadius),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      barrierColor: scrim,
      shape: const RoundedRectangleBorder(borderRadius: dialogRadius),
    ),
  );
}
