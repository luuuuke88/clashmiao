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
/// - [onTap]、[onLongPress] 都为空时视为禁用：没有反馈、不吃手势、不可聚焦，
///   语义上是「不可用的按钮」。
/// - 键盘 / 遥控：可聚焦（Tab 遍历），Enter / Space 触发 [onTap]（只有
///   [onLongPress] 时触发它——键盘没有长按）。键盘聚焦时在内容外圈画一圈跟随主题
///   主色的描边（[focusBorderRadius] 要和内容的圆角对上）；触屏下不画。
/// - 读屏：组件自己带 `button` 语义（含 enabled、点按 / 长按动作），调用点不用
///   再包 `Semantics(button: true)`；要读出标签 / 选中态时传 [semanticLabel] 或在外面
///   包 `Semantics`（会合并成同一个节点）。内容里另有控件承担语义（例如整行里的
///   `Switch`）时传 [excludeFromSemantics]。
/// - 时长与曲线走 [Motion] 的 token。系统开了「减少动画」时不缩放（缩放本身就是
///   位移动画），只做瞬时的变淡，反馈依然看得见；动画进行到一半打开它，立刻收到
///   终态。
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.behavior,
    this.excludeFromSemantics = false,
    this.semanticLabel,
    this.pressedScale = defaultPressedScale,
    this.focusBorderRadius = defaultFocusBorderRadius,
  });

  /// 卡片、胶囊这类较大的元素的缩放比例。
  static const double defaultPressedScale = 0.97;

  /// 图标按钮、导航图标这类小元素：缩得更明显才看得出。
  static const double iconPressedScale = 0.9;

  /// 按下时的不透明度。
  static const double pressedOpacity = 0.8;

  /// 键盘焦点描边的默认圆角。
  static const BorderRadius defaultFocusBorderRadius = BorderRadius.all(
    Radius.circular(16),
  );

  /// 键盘焦点描边的线宽与外扩距离（描边画在内容外面，不占布局）。
  static const double focusRingWidth = 2;
  static const double focusRingGap = 2;

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final HitTestBehavior? behavior;

  /// 为 true 时本组件不提供任何按钮语义（调用点或内容自己负责）。
  final bool excludeFromSemantics;

  /// 读屏标签；为空时由内容里的文字合成。
  final String? semanticLabel;

  /// 按下时的缩放（减少动画时忽略）。
  final double pressedScale;

  /// 键盘焦点描边的圆角，应与内容外形一致（圆按钮传其半径）。
  final BorderRadius focusBorderRadius;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.short,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Motion.standard,
  );

  bool _pressed = false;
  bool _focusVisible = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;
  bool get _active => _pressed && _enabled;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
    _syncController(animate: true);
  }

  /// 把控制器带到当前目标。减少动画时直接落在终点，不播过渡。
  void _syncController({required bool animate}) {
    final target = _active ? 1.0 : 0.0;
    if (!animate || Motion.reduced(context)) {
      _controller.value = target;
      return;
    }
    _controller.animateTo(target);
  }

  @override
  void didUpdateWidget(PressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 按住期间被禁用：onTapUp / onTapCancel 不会再来，自己把状态收回。
    if (_pressed && !_enabled) {
      _pressed = false;
      _syncController(animate: true);
    }
    if (!_enabled && _focusVisible) _focusVisible = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _activate() {
    (widget.onTap ?? widget.onLongPress)?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);

    // 自己拼 Opacity / Transform，而不是 AnimatedOpacity / AnimatedScale：后两者
    // 会在树里常驻 FadeTransition，外层按「最近的 FadeTransition」找入场动画的
    // 代码会被它截胡；这里不按时不产生任何额外的转场节点（Opacity 为 1 时也不开
    // 离屏层）。
    final content = AnimatedBuilder(
      animation: _progress,
      child: widget.child,
      // 层级固定（Opacity → Transform → child），不随按下与否增删：子树里有
      // 带状态的组件（呼吸动画之类）时，换层级会让它丢状态。
      builder: (context, child) {
        final t = _progress.value;
        return Opacity(
          opacity: 1 + (PressFeedback.pressedOpacity - 1) * t,
          child: Transform.scale(
            scale: reduced ? 1 : 1 + (widget.pressedScale - 1) * t,
            child: child,
          ),
        );
      },
    );

    final ringColor = Theme.of(context).colorScheme.primary;
    final ringOutset =
        PressFeedback.focusRingGap + PressFeedback.focusRingWidth;

    // 描边在缩放层外面、不占布局：按下缩小时它不跟着缩，也不会把周围挤开。
    final withRing = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        content,
        if (_focusVisible && _enabled)
          Positioned(
            left: -ringOutset,
            top: -ringOutset,
            right: -ringOutset,
            bottom: -ringOutset,
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey('press-feedback-focus-ring'),
                decoration: BoxDecoration(
                  borderRadius: widget.focusBorderRadius,
                  border: Border.all(
                    color: ringColor,
                    width: PressFeedback.focusRingWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final gesture = GestureDetector(
      behavior: widget.behavior,
      // 语义由下面的 Semantics 统一提供（带 button / enabled），不让
      // GestureDetector 再生成一份。
      excludeFromSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: _enabled ? (_) => _setPressed(true) : null,
      onTapUp: _enabled ? (_) => _setPressed(false) : null,
      onTapCancel: _enabled ? () => _setPressed(false) : null,
      child: withRing,
    );

    final semantic = widget.excludeFromSemantics
        ? gesture
        : Semantics(
            button: true,
            enabled: _enabled,
            label: widget.semanticLabel,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: gesture,
          );

    return FocusableActionDetector(
      enabled: _enabled,
      mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowFocusHighlight: (visible) {
        if (_focusVisible != visible && mounted) {
          setState(() => _focusVisible = visible);
        }
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: semantic,
    );
  }
}
