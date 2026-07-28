import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// 圆形的磨砂玻璃：背后内容被模糊掉，玻璃本身带一层品牌休眠色的染色和一道
/// 高光边。App 里所有"待机"的圆形品牌图形（空态那只睡觉的猫、未连接的连接
/// 按钮）都用它，保证同一种状态在两个地方是同一种材质。
///
/// 染色不是可选项：玻璃上压着的是一只**白猫**，纯透明的磨砂在浅色主题下等于
/// 白底白猫。[tintAlpha] 的下限要保证白色前景仍然读得出来。
///
/// 投影必须画在 [ClipOval] 外面——裁剪会把投影一起裁掉。
class FrostedDisc extends StatelessWidget {
  const FrostedDisc({
    required this.size,
    this.tintAlpha = 0.62,
    this.child,
    super.key,
  });

  final double size;

  /// 玻璃染色的不透明度。默认值是"白色前景还读得清"的下限附近，调低之前先
  /// 确认压在上面的东西不会消失。
  final double tintAlpha;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: BrandColors.indigoIdleDeep.withValues(alpha: 0.24),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      // 这里**故意不用 BackdropFilter**：这块圆盘挂在呼吸动画上，每帧缩放一次，
      // 而背景模糊每帧都要重新采样并开一个 saveLayer——首页的卡顿就是这么来的。
      // 圆盘底下是一整片平滑的品牌晕染，真模糊和半透明染色在观感上分不出来，
      // 那就没有理由为它每帧付一次代价。
      child: ClipOval(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // 左上偏亮、右下偏沉：一块玻璃的受光面，而不是一坨平涂的半透明。
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isLight
                  ? [
                      BrandColors.indigoIdle.withValues(alpha: tintAlpha),
                      BrandColors.indigoIdleDeep.withValues(
                        alpha: tintAlpha + 0.12,
                      ),
                    ]
                  : [
                      BrandColors.indigoIdleDeep.withValues(
                        alpha: tintAlpha * 0.55,
                      ),
                      BrandColors.indigoIdleDeep.withValues(
                        alpha: tintAlpha * 0.8,
                      ),
                    ],
            ),
            border: Border.all(
              color: isLight
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: child == null ? null : Center(child: child),
          ),
        ),
      ),
    );
  }
}
