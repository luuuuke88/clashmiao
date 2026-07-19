import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

/// 轻量的提示卡片：用来展示说明性的提示信息（例如"部分文件缺失，建议下载"、
/// "这是实验性功能"之类）。
///
/// 视觉上统一采用项目里占主导地位的玻璃拟态风格——背景/边框颜色取自
/// [AiUiTheme]（`aiUi.glassColor`/`aiUi.borderColor`），跟 `GlassCard`、
/// `AiUiModalWrapper`、`app_toast.dart` 等共享组件用的是同一套设计语言。
/// 在此之前，`config_options_page.dart` 和 `assets_page.dart` 各自维护了
/// 一份私有的 `_TipCard`，视觉风格互不一致（一个玻璃拟态、一个是朴素
/// `Card`）；本组件把两处收敛成同一个实现。
class TipCard extends StatelessWidget {
  const TipCard({
    super.key,
    required this.message,
    this.icon = FluentIcons.lightbulb_24_regular,
  });

  /// 提示文案。
  final String message;

  /// 提示图标，默认是灯泡。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: aiUi.glassColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: aiUi.borderColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Padding(padding: const EdgeInsets.all(8.0), child: Icon(icon)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(message),
            ),
          ),
        ],
      ),
    );
  }
}
