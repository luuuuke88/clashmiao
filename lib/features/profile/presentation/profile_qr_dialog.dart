import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 订阅二维码展示弹窗：把订阅链接（[data]，通常来自
/// `profiles_page.dart` 的 `profileShareUrl`，已经把订阅名编码进
/// URL fragment）渲染成二维码，供对方直接扫码导入。
///
/// 保持简单：只做展示，不做二维码自定义样式系统（logo 嵌入、多色渐变等）。
class ProfileQrDialog extends StatelessWidget {
  const ProfileQrDialog({
    super.key,
    required this.data,
    required this.profileName,
  });

  /// 二维码编码的完整内容（订阅 URL）。
  final String data;

  /// 弹窗标题展示用的订阅名（跟二维码内容分开传，方便测试各自断言）。
  final String profileName;

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;
    return AiUiModalWrapper(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profileName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: aiUi.borderColor),
              ),
              child: QrImageView(
                key: ValueKey('profile-qr-image-$data'),
                data: data,
                size: 220,
                semanticsLabel: '订阅二维码',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              data,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: aiUi.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
