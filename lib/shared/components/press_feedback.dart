import 'package:clashmiao/core/theme/motion.dart';
import 'package:flutter/material.dart';

/// 可点击区域的按下反馈：按下时内容轻微缩小并变淡，松手（或手指滑出 / 被滚动
/// 抢走手势）后回弹。
///
/// 项目里的卡片、胶囊、圆按钮是自绘的 `Container`，没有 Material 的墨水层，
/// 以前直接套 [GestureDetector]，按下去什么都不会发生——用户分不清「点到了」
/// 和「没点到」。凡是自绘的可点击元素都用它代替 [GestureDetector]；自带水波纹
/// 的 `ListTile` / `InkWell` 不需要。
///
/// - 手势识别在最外层，缩放只发生在里面：按下后命中区域不变小，手指在边缘
///   抖动不会触发 cancel。
/// - [onTap]、[onLongPress] 都为空时视为禁用：没有反馈、也不吃手势。
/// - 时长与曲线走 [Motion] 的 token。系统开了「减少动画」时不缩放（缩放本身就是
///   位移动画），只做瞬时的变淡，反馈依然看得见。
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior,
    this.excludeFromSemantics = false,
    this.pressedScale = defaultPressedScale,
  });

  /// 卡片、胶囊这类较大的元素的缩放比例。
  static const double defaultPressedScale = 0.97;

  /// 图标按钮、导航图标这类小元素：缩得更明显才看得出。
  static const double iconPressedScale = 0.9;

  /// 按下时的不透明度。
  static const double pressedOpacity = 0.8;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior? behavior;
  final bool excludeFromSemantics;

  /// 按下时的缩放（减少动画时忽略）。
  final double pressedScale;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(PressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 按住期间被禁用：onTapUp / onTapCancel 不会再来，自己把状态收回。
    if (_pressed && !_enabled) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final active = _pressed && _enabled;

    // 用 TweenAnimationBuilder 自己拼 Opacity / Transform，而不是
    // AnimatedOpacity / AnimatedScale：后两者会在树里常驻 FadeTransition，
    // 外层按「最近的 FadeTransition」找入场动画的代码会被它截胡；这里不按时
    // 不产生任何额外的转场节点（Opacity 为 1 时也不开离屏层）。
    final content = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1 : 0),
      duration: Motion.duration(context, Motion.short),
      curve: Motion.standard,
      child: widget.child,
      // 层级固定（Opacity → Transform → child），不随按下与否增删：子树里有
      // 带状态的组件（呼吸动画之类）时，换层级会让它丢状态。
      builder: (context, t, child) => Opacity(
        opacity: 1 + (PressFeedback.pressedOpacity - 1) * t,
        child: Transform.scale(
          scale: reduced ? 1 : 1 + (widget.pressedScale - 1) * t,
          child: child,
        ),
      ),
    );

    return GestureDetector(
      behavior: widget.behavior,
      excludeFromSemantics: widget.excludeFromSemantics,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      child: content,
    );
  }
}
