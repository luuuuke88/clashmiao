import 'dart:ui';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:flutter_hooks/flutter_hooks.dart';

/// 连接按钮 - 渐变圆形按钮，带涟漪动画和按压缓冲效果
class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({
    super.key,
    required this.status,
    required this.onTap,
  });

  final BoxStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final t = ref.watch(translationsProvider);

    final isConnected = status is BoxStarted;
    final isSwitching = status is BoxStarting || status is BoxStopping;

    final (
      Color glowColor,
      Color iconColor,
      IconData iconData,
      String statusText,
      List<Color> gradientColors,
    ) = switch (status) {
      BoxStarted() => (
        const Color(0xFF3B82F6),
        Colors.white,
        FluentIcons.shield_checkmark_24_regular,
        t.connection.connected,
        [const Color(0xFF3B82F6), const Color(0xFF6366F1)],
      ),
      BoxStarting() => (
        const Color(0xFF06B6D4), // Cyan Glow
        Colors.white,
        FluentIcons.arrow_sync_24_regular,
        t.connection.connecting,
        [
          const Color(0xFF06B6D4),
          const Color(0xFF3B82F6),
        ], // Gradient Cyan to Blue
      ),
      BoxStopping() => (
        const Color(0xFFF43F5E), // Rose Glow
        Colors.white,
        FluentIcons.arrow_sync_24_regular,
        t.connection.disconnecting,
        [const Color(0xFFF43F5E), const Color(0xFFE11D48)],
      ),
      BoxStopped() => (
        aiUi.borderColor,
        aiUi.secondaryTextColor,
        FluentIcons.power_24_regular,
        t.connection.tapToConnect,
        [aiUi.softBackgroundColor, aiUi.softBackgroundColor],
      ),
    };

    final scaleCtrl = useAnimationController(
      duration: 150.ms,
      lowerBound: 0.95,
      upperBound: 1.0,
      initialValue: 1.0,
    );

    return GestureDetector(
      onTapDown: (_) {
        if (!isSwitching) scaleCtrl.reverse();
      },
      onTapUp: (_) {
        scaleCtrl.forward();
        onTap();
      },
      onTapCancel: () => scaleCtrl.forward(),
      child: ScaleTransition(
        scale: scaleCtrl,
        child: Center(
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 涟漪效果（已连接时）
                if (isConnected) ...[
                  _RippleRing(color: glowColor, delay: 0.ms, scale: 1.4),
                  _RippleRing(color: glowColor, delay: 1000.ms, scale: 1.4),
                  _RippleRing(color: glowColor, delay: 2000.ms, scale: 1.4),
                ],

                // 呼吸发光底盘（切换中）
                if (isSwitching)
                  Container(
                        width: 204,
                        height: 204,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(0.95, 0.95),
                        end: const Offset(1.05, 1.05),
                        duration: 800.ms,
                      )
                      .fade(begin: 0.4, end: 1.0, duration: 800.ms),

                // 顺时针流光环（切换中）
                if (isSwitching)
                  Container(
                        width: 220,
                        height: 220,
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: ShaderMask(
                          shaderCallback: (rect) => SweepGradient(
                            colors: [
                              glowColor.withValues(alpha: 0.0),
                              glowColor.withValues(alpha: 0.2),
                              glowColor,
                              glowColor.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.5, 0.8, 1.0],
                          ).createShader(rect),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(duration: 1.2.seconds),

                // 逆时针细线星轨环（切换中）
                if (isSwitching)
                  Container(
                        width: 234,
                        height: 234,
                        decoration: const BoxDecoration(shape: BoxShape.circle),
                        child: ShaderMask(
                          shaderCallback: (rect) => SweepGradient(
                            colors: [
                              glowColor.withValues(alpha: 0.0),
                              glowColor.withValues(alpha: 0.6),
                              glowColor.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.3, 1.0],
                          ).createShader(rect),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .rotate(begin: 1.0, end: 0.0, duration: 2.seconds),

                // 主按钮
                AnimatedContainer(
                  duration: 500.ms,
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradientColors,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(
                          alpha: isConnected ? 0.4 : 0.05,
                        ),
                        blurRadius: isConnected ? 30 : 20,
                        spreadRadius: isConnected ? 5 : 0,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isConnected ? 0.2 : 0.05,
                      ),
                      width: 1,
                    ),
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: 300.ms,
                            transitionBuilder: (child, animation) {
                              return ScaleTransition(
                                scale: animation,
                                child: child,
                              );
                            },
                            child: isSwitching
                                ? Icon(
                                        iconData,
                                        key: const ValueKey('switching'),
                                        size: 64,
                                        color: iconColor,
                                      )
                                      .animate(onPlay: (c) => c.repeat())
                                      .rotate(duration: 2.seconds)
                                : Icon(
                                    iconData,
                                    key: ValueKey(iconData),
                                    size: 64,
                                    color: iconColor,
                                  ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            statusText.toUpperCase(),
                            style: TextStyle(
                              color: iconColor.withValues(alpha: 0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RippleRing extends StatelessWidget {
  final Color color;
  final Duration delay;
  final double scale;

  const _RippleRing({
    required this.color,
    required this.delay,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
          width: 190,
          height: 190,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat(), delay: delay)
        .scale(
          begin: const Offset(1, 1),
          end: Offset(scale, scale),
          duration: 3.seconds,
          curve: Curves.easeOut,
        )
        .fadeOut(begin: 0.5, duration: 3.seconds, curve: Curves.easeOut);
  }
}
