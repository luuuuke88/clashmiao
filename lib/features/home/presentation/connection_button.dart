import 'dart:async';

import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart' show Desired;
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/features/home/presentation/experimental_feature_notice_dialog.dart';
import 'package:clashmiao/features/home/presentation/sleeping_cat_aura.dart';
import 'package:clashmiao/features/home/presentation/speed_cat_connection_mark.dart';
import 'package:clashmiao/shared/components/frosted_disc.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 连接按钮 - 渐变圆形按钮，带涟漪动画。
///
/// 交互与状态语言（UI 设计 §2、连接状态机设计 §10.9）：
/// - 状态文字与可点击性**立即**跟随 [phase]，没有最短展示时长，过渡期也可点
///   （语义见 `toggleTarget`：连接中点 = 取消并断开，断开中点 = 重新连接）；
/// - 加载指示（圆盘外的细环）延迟 [ConnectionTiming.loadingIndicatorDelay]
///   才出现，防止快速成功 / 失败时一闪而过；成功或失败时立即消失；
/// - 只有猫与圆盘随 [scale] 缩放；状态文字固定 16 sp、计时 13 sp、等宽数字，
///   放不下时换行而不是缩小；
/// - 未连接的「点击连接」用 `onSurface`，圆盘保留低饱和品牌色，与禁用态区分。
class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({
    super.key,
    required this.phase,
    required this.onTap,
    this.scale = 1,
  });

  final ConnectionPhase phase;
  final VoidCallback onTap;

  /// 猫与圆盘相对设计尺寸（280 宽）的缩放；文字不缩放。
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);

    final isBusy =
        phase != ConnectionPhase.connected &&
        phase != ConnectionPhase.disconnected;
    // 尚无内核快照（resolving）时按「未连接」呈现：按钮可点，意图先被记录。
    final isIdle =
        phase == ConnectionPhase.disconnected ||
        phase == ConnectionPhase.resolving;
    // 只有真正连上了才"通电"：满饱和的品牌蓝留给已连接，其余状态（未连接、
    // 正在连接/断开）都是待机——用跟空态那只睡觉的猫同一块磨砂玻璃，让"亮起来"
    // 这件事只发生一次、且只在连上的那一刻。
    final isConnected = phase == ConnectionPhase.connected;

    final statusText = switch (phase) {
      ConnectionPhase.connected => t.connection.connected,
      ConnectionPhase.connecting ||
      ConnectionPhase.reconnecting => t.connection.connecting,
      ConnectionPhase.disconnecting => t.connection.disconnecting,
      ConnectionPhase.disconnected ||
      ConnectionPhase.resolving => t.connection.tapToConnect,
    };

    final label = Text(
      statusText.toUpperCase(),
      key: const ValueKey('connection-status-text'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isConnected
            ? BrandColors.connected
            : isIdle
            ? theme.colorScheme.onSurface
            : theme.aiUi.secondaryTextColor,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
    final startedAt = ref.watch(connectionStartedAtProvider);

    return GestureDetector(
      onTap: () => _handleConnectionTap(context, ref, onTap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _designWidth * scale,
            height: _designHeight * scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _designWidth,
                height: _designHeight,
                // 未连接 = 跟空态那只猫**完全一样**地睡着（同一个 SleepingCatAura：
                // 呼吸、z、柔光）；只有连上之后才分叉成通电的样子。
                child: SleepingCatAura(
                  discSize: _discSize,
                  asleep: isIdle,
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
                      // 猫压在底盘**上面**而不是塞进底盘里：标记图自带 47% 的
                      // 留白，尺寸得比底盘大一圈，猫脸才跟空态那只一样占满六成。
                      SpeedCatConnectionMark(
                        status: _markStatus(phase),
                        size: _discSize * 1.13,
                      ),
                      if (isBusy) const _DelayedLoadingRing(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 状态文字与计时独立于缩放布局：放不下时换行，不缩小字号。
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _designWidth),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 2,
              children: [
                label,
                if (isConnected && startedAt != null)
                  _ConnectedDuration(
                    key: const ValueKey('connection-duration'),
                    startedAt: startedAt,
                    color: theme.aiUi.secondaryTextColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 猫标记图只认「待机 / 激活中 / 已连接 / 停止中」四种展示态；由 phase 派生，
/// 不读任何内核状态。
BoxStatus _markStatus(ConnectionPhase phase) => switch (phase) {
  ConnectionPhase.connected => const BoxStarted(),
  ConnectionPhase.connecting ||
  ConnectionPhase.reconnecting => const BoxStarting(),
  ConnectionPhase.disconnecting => const BoxStopping(),
  ConnectionPhase.disconnected ||
  ConnectionPhase.resolving => const BoxStopped(),
};

/// 设计尺寸：猫 + 圆盘 + 柔光所占的方框（SleepingCatAura 占位 1.35 倍圆盘）。
const double _designWidth = 280;
const double _designHeight = 257;

/// 延迟出现的加载环（围在圆盘外）。每次进入过渡期重新计时；过渡结束时随着
/// 父级一起被移除，成功 / 失败立即消失。
class _DelayedLoadingRing extends StatefulWidget {
  const _DelayedLoadingRing();

  @override
  State<_DelayedLoadingRing> createState() => _DelayedLoadingRingState();
}

class _DelayedLoadingRingState extends State<_DelayedLoadingRing> {
  Timer? _timer;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(ConnectionTiming.loadingIndicatorDelay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: _discSize + 18,
      child: CircularProgressIndicator(
        key: const ValueKey('connection-loading-indicator'),
        strokeWidth: 2.5,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
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
        fontSize: 13,
        fontWeight: FontWeight.w400,
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

/// 连接前的门禁：只在"即将发起连接"时才检查是否要先弹实验性功能确认框；
/// 断开 / 取消连接不受影响，直接透传 [onTap]。"即将发起连接"与控制器 `toggle`
/// 的语义同源（`toggleTarget`），不在这里另算一遍。
/// 判断字段 + 弹窗 UI 见 experimental_feature_notice_dialog.dart。
Future<void> _handleConnectionTap(
  BuildContext context,
  WidgetRef ref,
  VoidCallback onTap,
) async {
  if (toggleTarget(ref.read(connectionControllerProvider)) == Desired.on) {
    final proceed = await maybeConfirmExperimentalFeatures(
      context: context,
      ref: ref,
    );
    if (!proceed) return;
  }
  onTap();
}
