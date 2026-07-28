import 'dart:math' as math;

import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// 开屏动画：品牌蓝底 + 中间那只猫打个招呼。
///
/// 原生启动图（iOS 的 LaunchScreen / Android 的 launch_background）用的是同一块
/// 蓝底和同一只猫、同样的尺寸，所以从"系统显示的静态图"切到这里时画面是接得上
/// 的——用户看到的是一只猫先出现、然后开始动，而不是闪一下换了张图。
///
/// 时长压在 1.5 秒以内：开屏动画再好看也是挡在用户和功能之间的东西。系统开了
/// "减弱动态效果"时直接跳过，只留一帧静态画面。
class SplashPage extends StatefulWidget {
  const SplashPage({required this.onFinished, super.key});

  /// 动画放完（或被减弱动态效果跳过）后回调，由外层换成真正的首页。
  final VoidCallback onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// 猫从小到大弹进来。
  late final Animation<double> _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.32, curve: Curves.easeOutBack),
  );

  /// 打招呼：左右各歪一次头。
  late final Animation<double> _wave = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.3, 0.72, curve: Curves.easeInOut),
  );

  /// "喵~" 气泡。
  late final Animation<double> _bubble = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.38, 0.6, curve: Curves.easeOutBack),
  );

  /// 名字。
  late final Animation<double> _wordmark = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 0.8, curve: Curves.easeOut),
  );

  var _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_finished) return;
    if (MediaQuery.of(context).disableAnimations) {
      // 减弱动态效果：不放动画，也不要硬留 1.5 秒白屏——直接放行。
      _controller.value = 1;
      _finish();
      return;
    }
    if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward().whenComplete(_finish);
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BrandColors.indigo, BrandColors.indigoDeep],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // 一来一回两次摆动，幅度逐次收小——像点头打招呼，不是节拍器。
              final swing =
                  math.sin(_wave.value * math.pi * 2) * (1 - _wave.value * 0.4);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 168,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Transform.scale(
                          key: const ValueKey('splash-cat-scale'),
                          scale: 0.62 + _pop.value * 0.38,
                          child: Transform.rotate(
                            angle: swing * 0.12,
                            child: Image.asset(
                              'assets/images/brand_mark.png',
                              key: const ValueKey('splash-cat'),
                              width: 168,
                              height: 168,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -6,
                          top: 14,
                          child: Transform.scale(
                            scale: _bubble.value,
                            alignment: Alignment.bottomLeft,
                            child: const _MiaoBubble(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: _wordmark.value.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(0, (1 - _wordmark.value) * 10),
                      child: const Text(
                        'ClashMiao',
                        key: ValueKey('splash-wordmark'),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 猫嘴边的那句招呼。
class _MiaoBubble extends StatelessWidget {
  const _MiaoBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('splash-bubble'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          // 左下角收尖，指向猫——气泡才有"从它嘴里出来"的意思。
          bottomLeft: Radius.circular(4),
        ),
        boxShadow: [
          BoxShadow(
            color: BrandColors.indigoDeep.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Text(
        'Hi 喵~',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: BrandColors.indigoDeep,
        ),
      ),
    );
  }
}
