import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

  /// 底部弹层的退场：比入场（[medium]）快一档，离开不拖泥带水。
  static const Duration sheetExit = Duration(milliseconds: 200);

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

  /// 给 [AnimatedSize] 这类**在布局期间驱动控制器**的动画用：减少动画时取 1 µs 而
  /// 不是 0。时长为 0 时控制器会在 `performLayout` 里同步通知监听者，触发
  /// 「RenderObject 在布局中被自己标脏」的断言；1 µs 在下一个 tick 就走完，
  /// 视觉上等同于立即完成。
  static Duration layoutDuration(BuildContext context, Duration token) =>
      reduced(context) ? const Duration(microseconds: 1) : token;

  /// 全部底部弹层（`showModalBottomSheet` / `showAiUiModal`）的统一转场：入场
  /// [medium] + [emphasized]、退场 [sheetExit] + [exit]；减少动画时无转场。
  ///
  /// 每个调用点都要传 `sheetAnimationStyle: Motion.sheetAnimation(context)`，不然
  /// 框架默认的 250/200 ms + 另一套曲线会让同一个 App 里的弹层各飞各的。
  static AnimationStyle sheetAnimation(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: medium,
          reverseDuration: sheetExit,
          curve: emphasized,
          reverseCurve: exit,
        );

  /// 取延迟：减少动画时清除。
  static Duration delay(BuildContext context, Duration delay) =>
      reduced(context) ? Duration.zero : delay;

  /// 循环动画（无限旋转之类）是否应当启动：减少动画时应显示静态状态。
  static bool loops(BuildContext context) => !reduced(context);
}

/// flutter_animate 的统一入口：用它代替 `.animate()`。
///
/// 系统开了「减少动画」时挂一个把时间轴放在终点的 [Adapter]：所有 `fadeIn` /
/// `slide` 的 duration 与 delay 都被跳过，内容立刻呈现终态；运行中途打开，
/// 适配器接上就把控制器跳到终点并停止。
///
/// 为什么用 adapter 而不是 `value`：关闭「减少动画」时，`value` 从 1 变回 null
/// 会让 flutter_animate 重新 `forward(from: 0)`，把已经显示完的内容又重播一遍。
/// 换成 adapter 的话，adapter 变成 null 只是卸掉适配器，**不会**触发重播——
/// 已完成的内容留在终态，只有之后新挂载的才播放入场。
extension MotionAnimate on Widget {
  Animate animateWithMotion(BuildContext context) =>
      animate(adapter: Motion.reduced(context) ? _EndStateAdapter() : null);
}

/// 接上控制器时把它放在终点（1.0）的适配器。
class _EndStateAdapter extends Adapter {
  @override
  void attach(AnimationController controller) => config(controller, 1);
}
