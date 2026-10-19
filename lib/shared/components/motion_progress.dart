import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';

/// 「进行中」指示器，圆形（默认构造）与线性（[MotionProgress.linear]）两种。
///
/// 正常时是不确定进度的转圈 / 来回扫动的进度条；系统开了「减少动画」时改画
/// **静态**的一段弧 / 一段条（不再循环），仍然看得出「进行中」。
///
/// 无障碍语义始终是「进度未知的加载中」（`loadingSpinner`，没有数值、没有
/// 0–100 范围）。静态形态靠 `value: …` 来画，但框架会据此自动生成
/// `progressBar` + 确定进度语义，所以那一层用 [ExcludeSemantics] 屏蔽，由外层
/// [Semantics] 重新声明未知进度。
///
/// 按钮内、行内的小转圈与整页加载占位（整页传 `strokeWidth: 4`，与框架默认
/// 粗细一致）统一用它，别直接写 `CircularProgressIndicator()`；不确定进度的
/// 线性条用 [MotionProgress.linear]，别直接写 `LinearProgressIndicator()`。
class MotionProgress extends StatelessWidget {
  const MotionProgress({super.key, this.strokeWidth = 2, this.color})
    : _linear = false,
      minHeight = null,
      backgroundColor = null;

  /// 不确定进度的线性条。[minHeight] / [backgroundColor] 同
  /// [LinearProgressIndicator]。
  const MotionProgress.linear({
    super.key,
    this.minHeight,
    this.backgroundColor,
    this.color,
  }) : _linear = true,
       strokeWidth = 2;

  final bool _linear;
  final double strokeWidth;
  final Color? color;
  final double? minHeight;
  final Color? backgroundColor;

  /// 减少动画时画出的静态弧占整圈的比例（只影响绘制，不进语义）。
  static const double staticArc = 0.75;

  /// 减少动画时线性条静态填充的比例（只影响绘制，不进语义）。
  static const double staticBar = 0.4;

  Widget _indicator({double? value}) => _linear
      ? LinearProgressIndicator(
          value: value,
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          color: color,
        )
      : CircularProgressIndicator(
          strokeWidth: strokeWidth,
          color: color,
          value: value,
        );

  @override
  Widget build(BuildContext context) {
    if (Motion.loops(context)) return _indicator();
    return Semantics(
      role: SemanticsRole.loadingSpinner,
      child: ExcludeSemantics(
        child: _indicator(value: _linear ? staticBar : staticArc),
      ),
    );
  }
}
