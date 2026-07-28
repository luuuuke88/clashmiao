import 'dart:math' as math;

import 'package:clashmiao/core/model/box_status.dart';
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

  /// 电流的抖动比呼吸快一个量级：1.2s 一轮，配合下面几个不同频率的正弦叠加，
  /// 出来的是"滋滋"的不规则闪烁，而不是规律的一亮一暗。
  late final AnimationController _crackleController;
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
    _crackleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
      _crackleController
        ..stop()
        ..value = 0;
      _activationController.forward(from: 0);
      return;
    }

    _activationController
      ..stop()
      ..value = 0;
    if (_isConnected) {
      _pulseController.repeat();
      _crackleController.repeat();
    } else {
      _pulseController
        ..stop()
        ..value = 0;
      _crackleController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _activationController.dispose();
    _pulseController.dispose();
    _crackleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('connection-speed-cat'),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _activationController,
          _pulseController,
          _crackleController,
        ]),
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
          // 滋滋冒电：三个互不整除的频率叠在一起，亮度就不会落回规律的
          // 一亮一暗，而是持续、不规则地窜。呼吸只负责底噪，抖动才是电流。
          final crackle = _isConnected && !_disableAnimations
              ? _crackle(_crackleController.value)
              : 0.0;
          final boltLift =
              _boltLift.value + (_isConnected ? -2 - connectedPulse * 2 : 0);
          final boltScale =
              _boltScale.value *
              (_isConnected
                  ? 1.03 + connectedPulse * 0.03 + crackle * 0.02
                  : 1);
          final boltGlow = _isConnected
              ? 0.13 + connectedPulse * 0.10 + crackle * 0.20
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
                if (_isConnected && !_disableAnimations)
                  for (var i = 0; i < _sparkCount; i++)
                    _Spark(
                      key: ValueKey('connection-spark-$i'),
                      size: widget.size,
                      // 每颗火花错开 1/N 个周期，只在自己那 30% 的窗口里
                      // 出现——同时全亮就成了装饰灯串，不是电弧。
                      phase: (_crackleController.value + i / _sparkCount) % 1,
                      index: i,
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
                      // 电流本体：一条高光顺着闪电从上端流到下端，走完一遍
                      // 立刻再来一遍。这才是"闪电在动"——外面窜的火花只是
                      // 伴生效果，主角是这条流动的光。
                      if (_isConnected && !_disableAnimations)
                        _BoltCurrent(
                          key: const ValueKey('connection-bolt-current'),
                          size: widget.size,
                          progress: (_crackleController.value * 2) % 1,
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

  /// 0..1 的不规则抖动。三个频率取素数比例，叠出来的波形在一个周期内不重复，
  /// 看起来就是电流那种没规律的窜动。
  double _crackle(double t) {
    final a = math.sin(t * math.pi * 2 * 6);
    final b = math.sin(t * math.pi * 2 * 11 + 1.7);
    final c = math.sin(t * math.pi * 2 * 17 + 0.4);
    return ((a * 0.5 + b * 0.32 + c * 0.18) + 1) / 2;
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
    final ringPulse = (pulse * 2) % 1;
    final haloBase = size * 1.02;
    // 光波要比 Logo 本身大，而 Stack 给子节点的是"最大不超过自己"的松约束，
    // 不解开的话 Container 会被压回 Logo 的尺寸——量出来永远等于 size，光波
    // 也就永远大不起来。
    return OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
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
          if (!disableAnimations)
            Transform.scale(
              scale: 1 + (ringPulse * 0.5),
              child: Opacity(
                opacity: (1 - ringPulse) * 0.26,
                child: Container(
                  width: haloBase,
                  height: haloBase,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: BrandColors.indigo, width: 1.25),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 电弧火花的数量。五颗够密到看着"在放电"，又不至于变成一圈装饰灯。
const int _sparkCount = 5;

/// 闪电周围窜出来的一小段电弧。
///
/// 画成一小节旋转过的圆头细条而不是圆点：圆点像星星，细条才像电。位置按
/// [size] 换算，围着闪电本体（大约占画布中间 27%×36%）的边缘转一圈。
class _Spark extends StatelessWidget {
  const _Spark({
    required super.key,
    required this.size,
    required this.phase,
    required this.index,
  });

  final double size;
  final double phase;
  final int index;

  /// 角度偏向闪电两端（右上、左下）——电从哪儿窜出来要跟闪电本身对得上。
  static const _angles = [-0.95, -0.55, 2.05, 2.5, 1.15];

  /// 半径落在猫脸之外、圆盘之内：白色火花压在白猫脸上等于没有，
  /// 落到靛蓝底盘上才亮得起来。
  static const _radii = [0.32, 0.3, 0.34, 0.31, 0.35];

  @override
  Widget build(BuildContext context) {
    // 只在自己那 30% 的窗口里出现：先窜出来再瞬间消失，跟电火花一样。
    const window = 0.45;
    if (phase > window) return const SizedBox.shrink();

    final t = phase / window;
    final opacity = (t < 0.35 ? t / 0.35 : 1 - (t - 0.35) / 0.65).clamp(
      0.0,
      1.0,
    );
    final angle = _angles[index % _angles.length];
    final radius = _radii[index % _radii.length] * size * (0.9 + t * 0.35);
    final length = size * (0.12 + t * 0.07);

    return Transform.translate(
      offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      child: Transform.rotate(
        angle: angle + math.pi / 2,
        child: Opacity(
          opacity: opacity * 0.9,
          child: Container(
            width: size * 0.016,
            height: length,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(size * 0.014),
              boxShadow: [
                BoxShadow(
                  color: BrandColors.gold.withValues(alpha: 0.95),
                  blurRadius: size * 0.08,
                  spreadRadius: size * 0.008,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顺着闪电流动的那道高光。
///
/// 做法是把一条移动的渐变当遮罩盖在闪电图层上（[BlendMode.srcIn]），所以亮
/// 的只有闪电本身的像素，看起来就是电流在闪电内部窜。渐变方向跟闪电的走向
/// 一致——右上到左下，跟图形本身的斜度对齐，不然会像一道无关的扫光。
class _BoltCurrent extends StatelessWidget {
  const _BoltCurrent({
    required super.key,
    required this.size,
    required this.progress,
  });

  final double size;

  /// 0→1：高光从闪电上端走到下端。
  final double progress;

  @override
  Widget build(BuildContext context) {
    // 渐变是按整张画布算的，而闪电只占画布中间那一小块（约 27%×36%）。
    // 让高光带只在闪电所在的区间里跑，不然一个周期里大半时间它都扫在
    // 透明区域上，看着就是"偶尔亮一下"而不是"一直在流动"。
    const band = 0.12;
    const start = 0.26;
    const end = 0.8;
    final head = start + progress * (end - start);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: const [
          Color(0x00FFFFFF),
          Color(0xCCFFFFFF),
          Color(0xFFFFFFFF),
          Color(0xCCFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [
          (head - band).clamp(0.0, 1.0),
          (head - band * 0.45).clamp(0.0, 1.0),
          head.clamp(0.0, 1.0),
          (head + band * 0.45).clamp(0.0, 1.0),
          (head + band).clamp(0.0, 1.0),
        ],
      ).createShader(rect),
      child: Image.asset(
        'assets/images/brand_bolt.png',
        width: size,
        height: size,
        color: Colors.white,
        colorBlendMode: BlendMode.srcIn,
      ),
    );
  }
}
