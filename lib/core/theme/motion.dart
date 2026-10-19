import 'package:flutter/material.dart';

/// 动效 token：只用于**普通反馈、开关切换、容器过渡**。
///
/// 呼吸周期、业务等待（连接中转圈）、超时、开屏动画不是"反馈"，不要往这里
/// 迁——它们的时长是产品语义的一部分，不是视觉节奏。
///
/// 系统开了「减少动画」（[MediaQuery.disableAnimationsOf]）时，一律通过
/// [Motion.duration] / [Motion.delay] / [Motion.loops] 取值：时长归零、延迟清除、
/// 循环动画不再启动，界面直接停在静态状态。
abstract final class Motion {
  /// 轻量反馈：选中态变色、开关、图标旋转。
  static const Duration short = Duration(milliseconds: 150);

  /// 容器过渡：尺寸变化、淡入淡出、页面级交叉淡出。
  static const Duration medium = Duration(milliseconds: 250);

  /// 较大幅度的过渡。
  static const Duration long = Duration(milliseconds: 400);

  /// 标准曲线（Material 3 standard）：状态在原地变化。
  static const Curve standard = Cubic(0.2, 0, 0, 1);

  /// 强调曲线（Material 3 emphasized decelerate）：元素进入、扩张。
  static const Curve emphasized = Cubic(0.05, 0.7, 0.1, 1);

  /// 退出曲线（Material 3 emphasized accelerate）：元素离开、收起。
  static const Curve exit = Cubic(0.3, 0, 0.8, 0.15);

  /// 系统是否要求减少动画。
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// 取 token 时长：减少动画时为 [Duration.zero]。
  static Duration duration(BuildContext context, Duration token) =>
      reduced(context) ? Duration.zero : token;

  /// 取延迟：减少动画时清除。
  static Duration delay(BuildContext context, Duration delay) =>
      reduced(context) ? Duration.zero : delay;

  /// 循环动画（无限旋转之类）是否应当启动：减少动画时应显示静态状态。
  static bool loops(BuildContext context) => !reduced(context);
}
