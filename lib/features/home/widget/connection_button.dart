import 'dart:async';

import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/experimental_feature_notice_dialog.dart';
import 'package:clashmiao/features/home/widget/sleeping_cat_aura.dart';
import 'package:clashmiao/features/home/widget/speed_cat_connection_mark.dart';
import 'package:clashmiao/shared/components/frosted_disc.dart';
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
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    final isSwitching = status is BoxStarting || status is BoxStopping;
    // 只有真正连上了才"通电"：满饱和的品牌蓝留给 BoxStarted，其余状态（未连接、
    // 正在连接/断开）都是待机——用跟空态那只睡觉的猫同一块磨砂玻璃，让"亮起来"
    // 这件事只发生一次、且只在连上的那一刻。
    final isConnected = status is BoxStarted;

    final statusText = switch (status) {
      BoxStarted() => t.connection.connected,
      BoxStarting() => t.connection.connecting,
      BoxStopping() => t.connection.disconnecting,
      BoxStopped() => t.connection.tapToConnect,
    };

    // 连接状态是整个 App 最重要的一条信息。首页会把整颗按钮缩到约 0.73 倍
    // （FittedBox 300 → 220），这里的 22 落到屏幕上大约 16pt——原来的 16 只剩
    // 不到 12pt，是全屏最不起眼的字之一。
    final label = Text(
      statusText.toUpperCase(),
      style: TextStyle(
        color: isConnected
            ? BrandColors.connected
            : theme.aiUi.secondaryTextColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );
    final startedAt = ref.watch(connectionStartedAtProvider);

    return GestureDetector(
      onTap: isSwitching
          ? null
          : () => _handleConnectionTap(context, ref, status, onTap),
      child: Center(
        child: SizedBox(
          width: 280,
          height: 300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 未连接 = 跟空态那只猫**完全一样**地睡着（同一个 SleepingCatAura：
              // 呼吸、z、柔光）；只有连上之后才分叉成通电的样子。
              SleepingCatAura(
                discSize: _discSize,
                asleep: status is BoxStopped,
                child: Stack(
                  alignment: Alignment.center,
                  // Logo 比底盘大一圈，不能被 Stack 裁掉。
                  clipBehavior: Clip.none,
                  children: [
                    if (isConnected)
                      const _ConnectedDisc()
                    else
                      const FrostedDisc(
                        key: ValueKey('connection-idle-disc'),
                        size: _discSize,
                      ),
                    // 猫压在底盘**上面**而不是塞进底盘里：标记图自带 47% 的留白，
                    // 尺寸得比底盘大一圈，猫脸才跟空态那只一样占满六成——作为
                    // 子节点会被底盘的紧约束压回 190，比例就跟外面对不上了。
                    SpeedCatConnectionMark(
                      status: status,
                      size: _discSize * 1.13,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 时长跟状态字放同一行：按钮是固定 280×300 再整体缩放的，另起一行
              // 会撑破高度；加高的话首页的 FittedBox 又会把整颗按钮缩得更小。
              // 最长的译文（俄语"点击连接"有 23 个字母）放大到 22 号会超出按钮
              // 宽度，放不下时整行等比缩小，而不是撑破或截断。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    label,
                    if (isConnected && startedAt != null) ...[
                      const SizedBox(width: 10),
                      _ConnectedDuration(
                        key: const ValueKey('connection-duration'),
                        startedAt: startedAt,
                        color: theme.aiUi.secondaryTextColor,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _discSize = 190;

/// 已连接时长，每秒走一次字。
///
/// 只在知道真实起点时出现（见 connectionStartedAtProvider）：挂上一条早就在跑
/// 的隧道时起点未知，宁可不显示也不从 0 开始数。
class _ConnectedDuration extends StatefulWidget {
  const _ConnectedDuration({
    super.key,
    required this.startedAt,
    required this.color,
  });

  final DateTime startedAt;
  final Color color;

  @override
  State<_ConnectedDuration> createState() => _ConnectedDurationState();
}

class _ConnectedDurationState extends State<_ConnectedDuration> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt);
    return Text(
      formatConnectedDuration(elapsed.isNegative ? Duration.zero : elapsed),
      style: TextStyle(
        color: widget.color,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 一小时内 `mm:ss`，超过一小时 `h:mm:ss`。
@visibleForTesting
String formatConnectedDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 已连接：满饱和的品牌蓝实心圆——整颗按钮"通电"，跟未连接时那块磨砂玻璃
/// 拉开的不只是明度，还有饱和度。
class _ConnectedDisc extends StatelessWidget {
  const _ConnectedDisc();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('connection-connected-disc'),
      width: _discSize,
      height: _discSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.indigo, BrandColors.indigoDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: BrandColors.indigo.withValues(alpha: 0.4),
            blurRadius: 30,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
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
