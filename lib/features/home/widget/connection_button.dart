import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/shared/components/experimental_feature_notice_dialog.dart';
import 'package:clashmiao/features/home/widget/speed_cat_connection_mark.dart';
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

    final isSwitching = status is BoxStarting || status is BoxStopping;

    final statusText = switch (status) {
      BoxStarted() => t.connection.connected,
      BoxStarting() => t.connection.connecting,
      BoxStopping() => t.connection.disconnecting,
      BoxStopped() => t.connection.tapToConnect,
    };

    return GestureDetector(
      onTap: isSwitching
          ? null
          : () => _handleConnectionTap(context, ref, status, onTap),
      child: Center(
        child: SizedBox(
          width: 280,
          height: 280,
          child: Center(
            child: Container(
              width: 190,
              height: 190,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpeedCatConnectionMark(status: status, size: 112),
                  const SizedBox(height: 6),
                  Text(
                    statusText.toUpperCase(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
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
