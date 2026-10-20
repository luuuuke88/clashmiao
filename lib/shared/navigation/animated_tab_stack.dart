import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/material.dart';

/// 底部导航的页面容器：[IndexedStack]（各页保活，切回来不丢滚动位置与状态）
/// 加上切换时新页面的淡入。
///
/// 以前切 tab 是硬切——整屏内容一帧之内换掉，旁边的导航图标也是瞬间变色，真机上
/// 像卡了一下。现在新页面用 [Motion.medium] / [Motion.standard] 从透明淡入，
/// 旧页面直接让位（背景晕染在最底层，所以不会闪黑）。
///
/// - 非当前页用 [TickerMode] 静音：里面的循环动画白白耗帧。
/// - 系统开了「减少动画」时直接显示终态，不淡入。
/// - 首次构建不淡入（冷启动已经有开屏到首页的交叉淡出）。
class AnimatedTabStack extends StatefulWidget {
  const AnimatedTabStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<AnimatedTabStack> createState() => _AnimatedTabStackState();
}

class _AnimatedTabStackState extends State<AnimatedTabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: 1,
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Motion.standard,
  );

  @override
  void didUpdateWidget(AnimatedTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (Motion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 淡入进行到一半时打开「减少动画」：直接收尾。
    if (Motion.reduced(context) && _controller.value < 1) {
      _controller.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: IndexedStack(
        index: widget.index,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            // 非当前 tab 虽然被 IndexedStack 藏起来了，但里面的 Ticker（循环
            // 动画、flutter_animate）照跑不误，白白耗帧。TickerMode 把它们
            // 静音；切回来时自动恢复。
            TickerMode(
              key: ValueKey('tab_ticker_$i'),
              enabled: i == widget.index,
              child: widget.children[i],
            ),
        ],
      ),
    );
  }
}
