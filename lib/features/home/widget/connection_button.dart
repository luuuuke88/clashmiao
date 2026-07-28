import 'package:clashmiao/core/model/box_status.dart';
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

    final label = Text(
      statusText.toUpperCase(),
      style: TextStyle(
        color: isConnected
            ? theme.colorScheme.primary
            : theme.aiUi.secondaryTextColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    );

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
              label,
            ],
          ),
        ),
      ),
    );
  }
}

const double _discSize = 190;

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
