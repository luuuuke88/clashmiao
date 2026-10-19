import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/material.dart';

/// 小号圆形「进行中」指示器：正常时是不确定进度的转圈；系统开了「减少动画」
/// 时改画一段**静态**的弧（不再无限旋转），仍然看得出「进行中」。
///
/// 按钮内、行内的小转圈统一用它，别直接写 `CircularProgressIndicator()`。
class MotionProgress extends StatelessWidget {
  const MotionProgress({super.key, this.strokeWidth = 2, this.color});

  final double strokeWidth;
  final Color? color;

  /// 减少动画时画出的静态弧占整圈的比例。
  static const double staticArc = 0.75;

  @override
  Widget build(BuildContext context) => CircularProgressIndicator(
    strokeWidth: strokeWidth,
    color: color,
    value: Motion.loops(context) ? null : staticArc,
  );
}
