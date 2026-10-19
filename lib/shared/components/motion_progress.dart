import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';

/// 小号圆形「进行中」指示器：正常时是不确定进度的转圈；系统开了「减少动画」
/// 时改画一段**静态**的弧（不再无限旋转），仍然看得出「进行中」。
///
/// 无障碍语义始终是「进度未知的加载中」（`loadingSpinner`，没有数值、没有
/// 0–100 范围）。静态弧靠 `CircularProgressIndicator(value: …)` 来画，但它会
/// 自动生成 `progressBar` + 75% 的确定进度语义，所以那一层用 [ExcludeSemantics]
/// 屏蔽，由外层 [Semantics] 重新声明未知进度。
///
/// 按钮内、行内的小转圈统一用它，别直接写 `CircularProgressIndicator()`。
class MotionProgress extends StatelessWidget {
  const MotionProgress({super.key, this.strokeWidth = 2, this.color});

  final double strokeWidth;
  final Color? color;

  /// 减少动画时画出的静态弧占整圈的比例（只影响绘制，不进语义）。
  static const double staticArc = 0.75;

  @override
  Widget build(BuildContext context) {
    if (Motion.loops(context)) {
      return CircularProgressIndicator(strokeWidth: strokeWidth, color: color);
    }
    return Semantics(
      role: SemanticsRole.loadingSpinner,
      child: ExcludeSemantics(
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color,
          value: staticArc,
        ),
      ),
    );
  }
}
