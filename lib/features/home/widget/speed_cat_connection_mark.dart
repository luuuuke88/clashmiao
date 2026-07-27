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
          return SizedBox.square(
            dimension: widget.size,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (_isConnected)
                  _ConnectedHalo(
                    pulse: pulse,
                    disableAnimations: _disableAnimations,
                  ),
                if (_showsRipple(activation, _ripple0Start))
                  _ActivationRipple(
                    key: const ValueKey('connection-ripple-0'),
                    progress: ripple0Progress,
                  ),
                if (_showsRipple(activation, _ripple1Start))
                  _ActivationRipple(
                    key: const ValueKey('connection-ripple-1'),
                    progress: ripple1Progress,
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
                    ..translateByDouble(0.0, _boltLift.value, 0.0, 1.0)
                    ..scaleByDouble(
                      _boltScale.value,
                      _boltScale.value,
                      _boltScale.value,
                      1.0,
                    ),
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
                        opacity: _boltGlow.value,
                        child: Image.asset(
                          'assets/images/brand_bolt.png',
                          width: widget.size,
                          height: widget.size,
                          color: Colors.white,
                          colorBlendMode: BlendMode.screen,
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
  const _ActivationRipple({required super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1 + (progress * 0.5),
      child: Opacity(
        opacity: (1 - progress) * 0.32,
        child: Container(
          width: 76,
          height: 76,
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
  const _ConnectedHalo({required this.pulse, required this.disableAnimations});

  final double pulse;
  final bool disableAnimations;

  @override
  Widget build(BuildContext context) {
    final pulsePhase = pulse <= 0.5 ? pulse * 2 : (1 - pulse) * 2;
    final haloPulse = disableAnimations
        ? 0.5
        : Curves.easeInOut.transform(pulsePhase);
    final ringPulse = (pulse * 2) % 1;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Container(
          key: const ValueKey('connection-blue-halo'),
          width: 84 + (haloPulse * 10),
          height: 84 + (haloPulse * 10),
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
            scale: 1 + (ringPulse * 0.35),
            child: Opacity(
              opacity: (1 - ringPulse) * 0.2,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: BrandColors.indigo, width: 1.25),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
