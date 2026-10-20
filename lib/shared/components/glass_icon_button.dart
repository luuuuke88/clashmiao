import 'package:clashmiao/shared/components/motion_progress.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/shared/components/press_feedback.dart';

/// 全 App 的圆形图标按钮：磨砂玻璃圆片。
///
/// 首页标题栏、线路页标题栏、设置页的问号——这些圆按钮以前各写各的（有的
/// 描 10% 黑边、有的用玻璃底、有的用凹槽色），并排放在一起一眼就能看出不是
/// 一套。统一到这里之后，材质跟卡片（`GlassCard`）和底部胶囊导航是同一种。
///
/// [filled] 留给页面上的主操作（首页那颗"+"）：实心品牌蓝，不走玻璃——主
/// 操作要跳出来，跟其它按钮一样透明就没有主次了。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.size = 40,
    this.iconSize = 20,
    this.tooltip,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double size;
  final double iconSize;

  /// 同时用作无障碍标签：圆按钮上只有一个图标，读屏没有文字可念。
  final String? tooltip;

  /// 进行中：图标换成同尺寸区域内的 18 dp 圆形进度指示器（按钮本身保持不变，
  /// 点击仍由 [onTap] 决定是否响应）。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    Widget glyph(Color color) => loading
        ? Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: MotionProgress(color: color),
            ),
          )
        : Icon(icon, size: iconSize, color: color);

    final Widget button = filled
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: aiUi.primaryShadow,
            ),
            child: glyph(theme.colorScheme.onPrimary),
          )
        // 跟 GlassCard 一样不用 BackdropFilter，理由见那边的注释。
        : ClipOval(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isLight
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isLight
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.14),
                ),
              ),
              child: glyph(
                isLight
                    ? aiUi.secondaryTextColor
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
          );

    // 视觉直径仍是 [size]（默认 40），交互区放大到至少 48×48（Material 与
    // Android 无障碍的最小触控目标）。热区放在 GestureDetector 里、圆本身
    // 居中，所以点圆外那一圈 4 dp 也算点中。
    final Widget tappable = PressFeedback(
      pressedScale: PressFeedback.iconPressedScale,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinInteractiveDimension,
          minHeight: kMinInteractiveDimension,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: RepaintBoundary(child: button),
        ),
      ),
    );

    // 真正构建 Tooltip：长按出可见的文字提示。无障碍标签由外层 Semantics 的
    // label 提供（Tooltip 的 excludeFromSemantics 打开，免得读屏把同一句话念
    // 两遍）。
    final label = tooltip;
    final Widget labelled = label == null
        ? tappable
        : Tooltip(message: label, excludeFromSemantics: true, child: tappable);

    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      child: labelled,
    );
  }
}
