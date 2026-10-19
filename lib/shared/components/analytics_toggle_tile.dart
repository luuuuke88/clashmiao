import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:clashmiao/shared/components/settings_row.dart';
import 'package:flutter/material.dart';

/// Analytics（数据分析）开关的统一 UI 外壳。
///
/// 使用项目里对"设置项 + 开关"占主导地位的单行样式——同样的图标 + 单行
/// 布局也用在 `settings_page.dart` 其它行（locale/主题/自动检查 IP 等）、
/// `config_options_page.dart` 的 `_ConfigGroup` 内部条目、
/// `profile_details_page.dart` 的 `_GlassContainer` 内部条目：三处都是"共享
/// 卡片容器 + 分隔线分隔的单行"。
///
/// 本组件只负责渲染，不接触持久化读写——[value]/[onChanged] 由调用方自己的
/// provider 提供。
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
  /// 完全一致（单行、最小 56 高）。
  final String? subtitle;

  final bool value;
  final ValueChanged<bool> onChanged;

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
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          );

    // 整行合并成一个语义节点（标题 + 开关状态 + 单一操作）。开关保持 48 dp
    // 点击目标；行上的 InkWell 不再另生成点击语义，免得出现两个可点节点。
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kSettingsRowMinHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: hasSubtitle ? 12 : 4,
            ),
            child: Row(
              children: [
                // 与设置页其它行一致：图标用中性色，不再单独染橙。
                ExcludeSemantics(
                  child: Icon(
                    FluentIcons.bug_24_regular,
                    size: 20,
                    color: aiUi.secondaryTextColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: labelColumn),
                const SizedBox(width: 8),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
