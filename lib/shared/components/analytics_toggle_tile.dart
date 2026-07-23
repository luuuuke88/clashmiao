import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

/// Analytics（数据分析）开关的统一 UI 外壳。
///
/// 之前 `settings_page.dart`（私有 `_BoolPreferenceTile`，强调色图标 + 单行
/// 样式）和 `onboarding_page.dart`（私有 `_IntroSwitchTile`，独立卡片样式）
/// 各自维护一份实现，控制的却是同一个持久化偏好（`clashmiao_analytics_enabled`），
/// 视觉风格互不一致。
///
/// 统一后选的是项目里对"设置项 + 开关"占主导地位的单行样式——同样的图标 +
/// 单行布局也用在 `settings_page.dart` 其它行（locale/主题/自动检查 IP 等）、
/// `config_options_page.dart` 的 `_ConfigGroup` 内部条目、
/// `profile_details_page.dart` 的 `_GlassContainer` 内部条目：三处都是"共享
/// 卡片容器 + 分隔线分隔的单行"，这是同类条目里出现频率最高的样式；
/// 相对地，"每项各自一张独立卡片"的样式只出现在 onboarding 自己的引导卡片
/// 和 `quick_settings_modal.dart` 的快捷开关里，属于少数。
///
/// 本组件只负责渲染，不接触持久化读写——[value]/[onChanged] 由调用方自己的
/// provider 提供，两处原有的读写逻辑保持不变。
class AnalyticsToggleTile extends StatelessWidget {
  const AnalyticsToggleTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  /// 主文案（例如"启用分析"，走 i18n）。
  final String label;

  /// 可选副标题说明。为 null 时不展示副标题，布局跟没有副标题的其它设置行
  /// 完全一致（单行、固定 56 高）。
  final String? subtitle;

  final bool value;
  final ValueChanged<bool> onChanged;

  static const _iconColor = Color(0xFFF97316);

  @override
  Widget build(BuildContext context) {
    final aiUi = Theme.of(context).aiUi;
    final hasSubtitle = subtitle != null;

    final labelColumn = hasSubtitle
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: aiUi.secondaryTextColor),
              ),
            ],
          )
        : Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          );

    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        height: hasSubtitle ? null : 56,
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: hasSubtitle ? 12 : 0,
        ),
        child: Row(
          children: [
            const Icon(FluentIcons.bug_24_regular, size: 20, color: _iconColor),
            const SizedBox(width: 16),
            Expanded(child: labelColumn),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
