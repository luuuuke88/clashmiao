import 'package:clashmiao/core/theme/motion.dart';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/config/presentation/config_options_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:clashmiao/shared/components/press_feedback.dart';

// 档位、选中态与写入都走 service_mode.dart 的唯一口径（与配置选项页一致）：
// 某个平台上不能生效的档位不出现（iOS 只有 VPN，桌面没有 TUN）。
String _quickServiceModeLabel(TranslationsEn t, ServiceMode mode) {
  return switch (mode) {
    ServiceMode.proxyOnly => t.config.shortServiceModes.proxy,
    ServiceMode.systemProxy => t.config.shortServiceModes.systemProxy,
    ServiceMode.vpn => t.config.shortServiceModes.tun,
  };
}

class QuickSettingsModal extends ConsumerWidget {
  const QuickSettingsModal({super.key});

  /// 以底部弹层路由打开。整个入场/退场动画只来自这一条路由（250/200 ms），
  /// 内容区没有任何二次位移或延迟；系统开了「减少动画」就直接不播。
  /// 表面是实色，不透出背后的页面。
  static Future<void> show(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      showDragHandle: true,
      backgroundColor: isDark
          ? const Color(0xFF1C1C22)
          : theme.colorScheme.surfaceContainerLow,
      barrierColor: Colors.black.withValues(alpha: 0.40),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: Motion.sheetAnimation(context),
      builder: (_) => const QuickSettingsModal(),
    );
  }

  Future<void> _changeServiceMode(WidgetRef ref, ServiceMode mode) =>
      applyServiceMode(ref.read(networkSettingsProvider.notifier), mode);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final settings = ref.watch(networkSettingsProvider);
    final selectedMode = serviceModeOf(settings);

    return AiUiModalWrapper(
      routeProvidesSurface: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
            child: Column(
              children: [
                Text(
                  t.config.quickSettings,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.config.quickSettingsSubtitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: theme.aiUi.secondaryTextColor,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.aiUi.softBackgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.aiUi.borderColor),
              ),
              child: Row(
                children: serviceModeChoices(settings).map((mode) {
                  final isSelected = selectedMode == mode;
                  // 只有一档（iOS 恒为 VPN）时不是可选控件：不暴露按钮语义、
                  // 点了也没有动作，边界由下面的说明文字交代。
                  final selectable = !serviceModeIsFixed;
                  return Expanded(
                    child: Semantics(
                      button: selectable,
                      selected: isSelected,
                      inMutuallyExclusiveGroup: selectable,
                      child: PressFeedback(
                        behavior: HitTestBehavior.opaque,
                        onTap: selectable
                            ? () => _changeServiceMode(ref, mode)
                            : null,
                        child: AnimatedContainer(
                          duration: reduceMotion ? Duration.zero : Motion.short,
                          // 最小 48 dp 的交互高度（Android 触控目标）；文字放大时
                          // 随内容增高。
                          constraints: const BoxConstraints(
                            minHeight: kMinInteractiveDimension,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? scheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _quickServiceModeLabel(t, mode),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? scheme.onPrimaryContainer
                                  : theme.aiUi.secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (serviceModeIsFixed) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                t.config.serviceModeIosVpnOnly,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.aiUi.secondaryTextColor,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                _SettingTile(
                  label: settings.warpConsentGiven
                      ? t.config.enableWarp
                      : t.config.setUpWarp,
                  trailingText: settings.warpConsentGiven
                      ? null
                      : t.config.warpNotConfigured,
                  value: settings.warpConsentGiven ? settings.enableWarp : null,
                  icon: FluentIcons.shield_24_regular,
                  onChanged: settings.warpConsentGiven
                      ? ref.read(networkSettingsProvider.notifier).setEnableWarp
                      : null,
                  onTap: settings.warpConsentGiven
                      ? null
                      : () => _pushConfigOptions(context),
                ),
                const SizedBox(height: 12),
                _SettingTile(
                  label: t.config.enableTlsFragment,
                  value: settings.enableTlsFragment,
                  icon: FluentIcons.leaf_one_24_regular,
                  onChanged: ref
                      .read(networkSettingsProvider.notifier)
                      .setEnableTlsFragment,
                ),
                const SizedBox(height: 12),
                _SettingTile(
                  label: t.config.allAdvancedOptions,
                  icon: FluentIcons.settings_24_regular,
                  onTap: () => _pushConfigOptions(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _pushConfigOptions(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConfigOptionsPage()));
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.label,
    this.value,
    required this.icon,
    this.trailingText,
    this.onChanged,
    this.onTap,
  });

  final String label;
  final bool? value;
  final IconData icon;

  /// 尾部的状态文字（例如 WARP 未授权时的「未配置」），显示在箭头之前。
  final String? trailingText;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  static const _labelStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
  );

  /// 状态文字与标题并排放得下吗？放不下就把状态文字挪到标题下面一行，
  /// 而不是挤压标题或溢出（窄屏 + 大字号 + 长翻译）。
  bool _statusFitsBesideLabel(BuildContext context, double rowWidth) {
    final status = trailingText;
    if (status == null) return true;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: base.merge(style)),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final labelWidth = measure(label, _labelStyle);
    final statusWidth = measure(status, const TextStyle(fontSize: 12));
    // 图标 32 + 间距 12 + 状态与标题间距 8 + 状态与箭头间距 4 + 箭头 16。
    const chrome = 32 + 12 + 8 + 4 + 16;
    return labelWidth + statusWidth + chrome <= rowWidth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = trailingText;
    final hasSwitch = onChanged != null && value != null;
    // 整行是一个语义节点：开关行读作「标题、开关、已开启/已关闭」，点哪都能切；
    // 入口行读作按钮。不合并的话读屏会把标题、开关、箭头拆成三四个焦点。
    return MergeSemantics(
      child: Semantics(
        button: !hasSwitch,
        child: PressFeedback(
          // 开关行的点击语义交给里面的 Switch，免得同一动作暴露两次。
          excludeFromSemantics: hasSwitch,
          onTap:
              onTap ?? (onChanged != null ? () => onChanged!(!value!) : null),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.aiUi.softBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.aiUi.borderColor),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final inline =
                    status != null &&
                    !hasSwitch &&
                    _statusFitsBesideLabel(context, constraints.maxWidth);
                final stacked = status != null && !hasSwitch && !inline;
                final statusStyle = TextStyle(
                  fontSize: 12,
                  color: theme.aiUi.secondaryTextColor,
                );
                return Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        // 图标统一用品牌 primary 的低饱和底：绿/橙/红只留给状态。
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: theme.colorScheme.primary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: _labelStyle),
                          if (stacked) ...[
                            const SizedBox(height: 2),
                            Text(status, style: statusStyle),
                          ],
                        ],
                      ),
                    ),
                    if (hasSwitch)
                      SizedBox(
                        height: 32,
                        child: Switch.adaptive(
                          value: value!,
                          onChanged: onChanged,
                        ),
                      )
                    else ...[
                      if (inline) ...[
                        const SizedBox(width: 8),
                        Text(status, style: statusStyle),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        FluentIcons.chevron_right_24_regular,
                        size: 16,
                        color: theme.aiUi.secondaryTextColor,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
