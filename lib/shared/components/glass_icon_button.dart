import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';

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
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double size;
  final double iconSize;

  /// 同时用作无障碍标签：圆按钮上只有一个图标，读屏没有文字可念。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    final Widget button = filled
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
              boxShadow: aiUi.primaryShadow,
            ),
            child: Icon(icon, size: iconSize, color: Colors.white),
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
              child: Icon(
                icon,
                size: iconSize,
                color: isLight
                    ? aiUi.secondaryTextColor
                    : Colors.white.withValues(alpha: 0.8),
              ),
            ),
          );

    return Semantics(
      label: tooltip,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: RepaintBoundary(child: button),
      ),
    );
  }
}
