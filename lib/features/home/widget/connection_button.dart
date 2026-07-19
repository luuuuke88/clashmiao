import 'dart:ui';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/experimental_feature_notice_dialog.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 连接按钮 - 渐变圆形按钮，带涟漪动画。
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
        const Color(0xFFEAB308),
        Colors.white,
        FluentIcons.arrow_sync_24_regular,
        t.connection.connecting,
        [const Color(0xFFF59E0B), const Color(0xFFD97706)],
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

    return GestureDetector(
      onTap: isSwitching
          ? null
          : () => _handleConnectionTap(context, ref, status, onTap),
      child: Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isConnected) ...[
                _RippleRing(color: glowColor, delay: 0.ms, scale: 1.4),
                _RippleRing(color: glowColor, delay: 1000.ms, scale: 1.4),
                _RippleRing(color: glowColor, delay: 2000.ms, scale: 1.4),
              ],
              if (isSwitching)
                Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: glowColor.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 2.seconds),
              if (isSwitching)
                SizedBox(
                      width: 220,
                      height: 220,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: glowColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: glowColor.withValues(alpha: 0.6),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .rotate(duration: 2.seconds),
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
                          child: Icon(
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
    );
  }
}

/// 连接前的门禁：只在"即将发起连接"（当前是 BoxStopped）时才检查是否要先弹
/// 实验性功能确认框；断开 / 切换中点击不受影响，直接透传 [onTap]。
/// 判断字段 + 弹窗 UI 见 experimental_feature_notice_dialog.dart，这里只加
/// 这一层门禁，不改动 [onTap] 本身的调用逻辑。
Future<void> _handleConnectionTap(
  BuildContext context,
  WidgetRef ref,
  BoxStatus status,
  VoidCallback onTap,
) async {
  if (status is BoxStopped) {
    final proceed = await maybeConfirmExperimentalFeatures(
      context: context,
      ref: ref,
    );
    if (!proceed) return;
  }
  onTap();
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
