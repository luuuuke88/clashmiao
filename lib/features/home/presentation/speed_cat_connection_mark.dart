import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

class SpeedCatConnectionMark extends StatefulWidget {
  const SpeedCatConnectionMark({
    required this.status,
    this.size = 112,
    super.key,
  });

  final BoxStatus status;
  final double size;

  @override
  State<SpeedCatConnectionMark> createState() => _SpeedCatConnectionMarkState();
}

class _SpeedCatConnectionMarkState extends State<SpeedCatConnectionMark>
    with TickerProviderStateMixin {
  static const _ripple0Start = 120 / 600;
  static const _ripple1Start = 250 / 600;

  late final AnimationController _activationController;
  late final AnimationController _pulseController;
  late final Animation<double> _boltLift;
  late final Animation<double> _boltScale;
  late final Animation<double> _boltGlow;

  var _disableAnimations = false;
  var _hasMediaQuery = false;

  bool get _isActivating => widget.status is BoxStarting;

  bool get _isConnected => widget.status is BoxStarted;

  @override
  void initState() {
    super.initState();
    _activationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _boltLift = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: -8.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 37,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: -8.0,
          end: -2.0,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 63,
      ),
    ]).animate(_activationController);
    _boltScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 37,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 1.04,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 63,
      ),
    ]).animate(_activationController);
    _boltGlow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.04,
          end: 0.38,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 37,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.38,
          end: 0.12,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 63,
      ),
    ]).animate(_activationController);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    if (!_hasMediaQuery || _disableAnimations != disableAnimations) {
      _hasMediaQuery = true;
      _disableAnimations = disableAnimations;
      _syncAnimations();
    }
  }

  @override
  void didUpdateWidget(covariant SpeedCatConnectionMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.runtimeType != widget.status.runtimeType) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (_disableAnimations) {
      _activationController
        ..stop()
        ..value = _isActivating ? 1 : 0;
      _pulseController
        ..stop()
        ..value = 0;
      return;
    }

    if (_isActivating) {
      _pulseController
        ..stop()
        ..value = 0;
      _activationController.forward(from: 0);
      return;
    }

    _activationController
      ..stop()
      ..value = 0;
    // 连上之后只留一下慢呼吸。曾经还有电火花乱窜、高光顺着闪电流动、光环
    // 往外扩——一直在动的按钮读起来就是"还在连接"，跟"已连接"正好相反。
    if (_isConnected) {
      _pulseController.repeat();
    } else {
      _pulseController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _activationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('connection-speed-cat'),
      child: AnimatedBuilder(
        animation: Listenable.merge([_activationController, _pulseController]),
        builder: (context, child) {
          final activation = _activationController.value;
          final pulse = _pulseController.value;
          final ripple0Progress = _intervalProgress(activation, _ripple0Start);
          final ripple1Progress = _intervalProgress(activation, _ripple1Start);
          // 已连接 = 活力满满：闪电不落回静止位，而是保持微微上抬、放大，并跟着
          // 呼吸一亮一暗。连接中那一下是"通电的瞬间"，连上之后是"持续供电"。
          final breath = pulse <= 0.5 ? pulse * 2 : (1 - pulse) * 2;
          final connectedPulse = _isConnected && !_disableAnimations
              ? Curves.easeInOut.transform(breath)
              : 0.0;
          final boltLift =
              _boltLift.value + (_isConnected ? -2 - connectedPulse * 2 : 0);
          final boltScale =
              _boltScale.value *
              (_isConnected ? 1.03 + connectedPulse * 0.03 : 1);
          final boltGlow = _isConnected
              ? 0.13 + connectedPulse * 0.14
              : _boltGlow.value;
          return SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (_isConnected)
                  _ConnectedHalo(
                    pulse: pulse,
                    size: widget.size,
                    disableAnimations: _disableAnimations,
                  ),
                if (_showsRipple(activation, _ripple0Start))
                  _ActivationRipple(
                    key: const ValueKey('connection-ripple-0'),
                    progress: ripple0Progress,
                    size: widget.size,
                  ),
                if (_showsRipple(activation, _ripple1Start))
                  _ActivationRipple(
                    key: const ValueKey('connection-ripple-1'),
                    progress: ripple1Progress,
                    size: widget.size,
                  ),
                Image.asset(
                  'assets/images/brand_cat.png',
                  key: const ValueKey('connection-cat-layer'),
                  width: widget.size,
                  height: widget.size,
                ),
                Transform(
                  key: const ValueKey('connection-bolt-transform'),
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translateByDouble(0.0, boltLift, 0.0, 1.0)
                    ..scaleByDouble(boltScale, boltScale, boltScale, 1.0),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/images/brand_bolt.png',
                        key: const ValueKey('connection-bolt-layer'),
                        width: widget.size,
                        height: widget.size,
                      ),
                      Opacity(
                        key: const ValueKey('connection-bolt-glow'),
                        opacity: boltGlow,
                        child: Image.asset(
                          'assets/images/brand_bolt.png',
                          width: widget.size,
                          height: widget.size,
                          // 用 srcIn 把闪电染成纯白再叠上去，而不是 screen。
                          //
                          // screen 属于要读取"底下已经画了什么"的混合模式，
                          // Impeller 会为此开一个 saveLayer；连上之后这层辉光
                          // 常驻且不透明度拉高，那个图层的矩形边界就在按钮四周
                          // 显出来一个方框。srcIn 只作用于图片自身像素，不碰
                          // 背景，观感一样但不会留下框。
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _showsRipple(double activation, double start) {
    return _isActivating &&
        !_disableAnimations &&
        activation >= start &&
        activation < 1;
  }

  double _intervalProgress(double activation, double start) {
    return ((activation - start) / (1 - start)).clamp(0.0, 1.0);
  }
}

class _ActivationRipple extends StatelessWidget {
  const _ActivationRipple({
    required super.key,
    required this.progress,
    required this.size,
  });

  final double progress;

  /// 光圈跟着 Logo 的尺寸走：这个组件既会单独用（112），也会压在首页那颗
  /// 190 的按钮上（更大）。写死像素的话，大按钮上的光圈会缩在猫脸里，
  /// "从中心扩散出去"就完全看不见了。
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1 + (progress * 0.65),
      child: Opacity(
        opacity: (1 - progress) * 0.32,
        child: Container(
          width: size * 0.8,
          height: size * 0.8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: BrandColors.indigo, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _ConnectedHalo extends StatelessWidget {
  const _ConnectedHalo({
    required this.pulse,
    required this.size,
    required this.disableAnimations,
  });

  final double pulse;

  /// 跟 [_ActivationRipple.size] 同一个理由：光晕要绕在 Logo **外圈**，
  /// 尺寸必须跟着 Logo 走，写死像素在大按钮上就被猫脸盖住了。
  final double size;

  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final pulsePhase = pulse <= 0.5 ? pulse * 2 : (1 - pulse) * 2;
    final haloPulse = disableAnimations
        ? 0.5
        : Curves.easeInOut.transform(pulsePhase);
    final haloBase = size * 1.02;
    // 光波要比 Logo 本身大，而 Stack 给子节点的是"最大不超过自己"的松约束，
    // 不解开的话 Container 会被压回 Logo 的尺寸——量出来永远等于 size，光波
    // 也就永远大不起来。
    return OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Container(
        key: const ValueKey('connection-blue-halo'),
        width: haloBase + (haloPulse * size * 0.13),
        height: haloBase + (haloPulse * size * 0.13),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: BrandColors.indigo.withValues(
            alpha: 0.08 + (haloPulse * 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: BrandColors.indigoDeep.withValues(
                alpha: 0.14 + (haloPulse * 0.1),
              ),
              blurRadius: 20 + (haloPulse * 12),
              spreadRadius: 2 + (haloPulse * 3),
            ),
          ],
        ),
      ),
    );
  }
}
