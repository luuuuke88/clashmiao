import 'dart:math' as math;

import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// 让一只猫"睡着"：呼吸起伏 + 右上角飘三个 z + 一圈随呼吸浓淡的柔光。
///
/// 空态那只猫和首页未连接时的连接按钮共用它——两处画的是同一只猫，休眠的样子
/// 就该一模一样，只有连上之后才分叉（那时 [asleep] 传 false，这里全部让位给
/// `SpeedCatConnectionMark` 的通电光晕）。
///
/// 尺寸全部按 [discSize] 换算：同一套动效要同时挂在 132 的空态圆盘和 190 的
/// 连接按钮上，写死像素的话 z 会飘错位置、柔光会缩在猫脸里。
///
/// 系统开了"减弱动态效果"时呼吸和飘动都停，z 停在一组错开的静止位置上——
/// 语义还在，只是不动。
class SleepingCatAura extends StatefulWidget {
  const SleepingCatAura({
    required this.discSize,
    required this.child,
    this.asleep = true,
    super.key,
  });

  /// 圆盘直径。柔光、z 的落点和字号都按它换算。
  final double discSize;

  /// false = 醒着（已连接）：不呼吸、不飘 z、不画柔光，只渲染 [child]。
  final bool asleep;

  final Widget child;

  @override
  State<SleepingCatAura> createState() => _SleepingCatAuraState();
}

class _SleepingCatAuraState extends State<SleepingCatAura>
    with TickerProviderStateMixin {
  /// 一呼一吸 3.4s：比清醒时的心跳慢，快了就不像睡着了。
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );
  late final AnimationController _zzz = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  var _disableAnimations = false;
  var _hasMediaQuery = false;

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
  void didUpdateWidget(covariant SleepingCatAura oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asleep != widget.asleep) _syncAnimations();
  }

  void _syncAnimations() {
    if (_disableAnimations || !widget.asleep) {
      _breath
        ..stop()
        ..value = 0;
      _zzz
        ..stop()
        ..value = 0;
      return;
    }
    _breath.repeat(reverse: true);
    _zzz.repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    _zzz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 占位只留到 1.35 倍：柔光和 z 都靠 Stack 的 clipBehavior: none 画到框外，
    // 不该让它们把整块布局撑大——连接按钮那边 190 的圆盘再乘 1.52 就顶穿了
    // 外层 280 的方框。
    final box = widget.discSize * 1.35;
    final glow = widget.discSize * 1.52;

    if (!widget.asleep) {
      return SizedBox.square(
        dimension: box,
        child: Center(child: widget.child),
      );
    }

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: box,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _zzz]),
          builder: (context, _) {
            final breath = Curves.easeInOut.transform(_breath.value);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _Glow(size: glow, breath: breath),
                Transform.translate(
                  // 吸气时轻轻抬起，呼气时沉回去——位移只有圆盘的 2%，
                  // 多了就成了漂浮。
                  offset: Offset(0, (1 - breath) * widget.discSize * 0.023),
                  child: Transform.scale(
                    scale: 1 + breath * 0.035,
                    child: widget.child,
                  ),
                ),
                for (var i = 0; i < 3; i++)
                  _SleepZ(
                    key: ValueKey('sleep-zzz-$i'),
                    discSize: widget.discSize,
                    // 三个 z 各差 1/3 个周期；静止时也铺开成一串，
                    // 而不是三个叠在同一个点上。
                    phase: _disableAnimations
                        ? 0.25 + i * 0.22
                        : (_zzz.value + i / 3) % 1,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.breath});

  final double size;
  final double breath;

  @override
  Widget build(BuildContext context) {
    // 渐变常量化，只用 Opacity 调深浅：把 alpha 揉进渐变色里的话，每一帧都要
    // 重新构造一次 shader，呼吸动画就会一顿一顿的。
    return Opacity(
      opacity: 0.72 + breath * 0.28,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Color(0x2EB5B5D9), Color(0x00B5B5D9)],
          ),
        ),
      ),
    );
  }
}

/// 一个往右上角飘走的 z：升高、放大、先淡入后淡出，末尾轻轻向外偏。
class _SleepZ extends StatelessWidget {
  const _SleepZ({
    required super.key,
    required this.phase,
    required this.discSize,
  });

  final double phase;
  final double discSize;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(phase);
    // 前 22% 淡入、后 45% 淡出，中间保持——避免三个 z 同时半透明糊成一团。
    final double fade;
    if (phase < 0.22) {
      fade = phase / 0.22;
    } else if (phase > 0.55) {
      fade = 1 - (phase - 0.55) / 0.45;
    } else {
      fade = 1;
    }

    final unit = discSize / 132;
    return Transform.translate(
      offset: Offset((46 + eased * 22) * unit, (-46 - eased * 46) * unit),
      child: Transform.rotate(
        angle: math.pi / 18 * (1 - eased),
        child: Opacity(
          opacity: (fade * 0.75).clamp(0, 1),
          child: Text(
            'z',
            style: TextStyle(
              fontSize: (15 + eased * 13) * unit,
              fontWeight: FontWeight.w800,
              height: 1,
              color: BrandColors.indigoIdleDeep.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}
