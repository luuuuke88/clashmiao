import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/material.dart';

/// 选中对勾、箭头这类「出现 / 消失 / 互换」的小标记：淡入淡出 + 轻微缩放，而不是
/// 一帧之内蹦出来或消失。
///
/// [child] 为空表示没有标记。两个都是 `Icon` 的标记互换时，调用方要给它们
/// 不同的 `key`，否则 [AnimatedSwitcher] 会把它们当成同一个组件而不播过渡。
/// 时长走 [Motion.short]，减少动画时瞬时切换。
class AnimatedMark extends StatelessWidget {
  const AnimatedMark({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.duration(context, Motion.short),
      switchInCurve: Motion.emphasized,
      switchOutCurve: Motion.standard,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
          child: child,
        ),
      ),
      child:
          child ?? const SizedBox.shrink(key: ValueKey('animated-mark-none')),
    );
  }
}
