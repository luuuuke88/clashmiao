import 'dart:io';

import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/config/widget/config_options_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum _QuickServiceMode { proxy, systemProxy, tun }

/// 桌面端不给 TUN 档，理由见 `config_options_page.dart` 里同名函数
/// `_serviceModeChoices` 的文档（没有 wintun 驱动、没有网络扩展权限，
/// 选了必定失败）。两处必须保持一致，否则用户能从快捷设置绕过这条限制。
List<_QuickServiceMode> get _quickServiceModeChoices {
  if (Platform.isAndroid || Platform.isIOS) {
    return const [_QuickServiceMode.proxy, _QuickServiceMode.tun];
  }
  return const [_QuickServiceMode.proxy, _QuickServiceMode.systemProxy];
}

_QuickServiceMode _quickServiceModeOf(NetworkSettings settings) {
  if (settings.enableTun) return _QuickServiceMode.tun;
  if (settings.setSystemProxy) return _QuickServiceMode.systemProxy;
  return _QuickServiceMode.proxy;
}

String _quickServiceModeLabel(TranslationsEn t, _QuickServiceMode mode) {
  return switch (mode) {
    _QuickServiceMode.proxy => t.config.shortServiceModes.proxy,
    _QuickServiceMode.systemProxy => t.config.shortServiceModes.systemProxy,
    _QuickServiceMode.tun => t.config.shortServiceModes.tun,
  };
}

class QuickSettingsModal extends ConsumerWidget {
  const QuickSettingsModal({super.key});

  Future<void> _changeServiceMode(WidgetRef ref, _QuickServiceMode mode) async {
    final notifier = ref.read(networkSettingsProvider.notifier);
    switch (mode) {
      case _QuickServiceMode.proxy:
        await notifier.setEnableTun(false);
        await notifier.setSystemProxy(false);
      case _QuickServiceMode.systemProxy:
        await notifier.setEnableTun(false);
        await notifier.setSystemProxy(true);
      case _QuickServiceMode.tun:
        await notifier.setSystemProxy(false);
        await notifier.setEnableTun(true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final settings = ref.watch(networkSettingsProvider);
    final selectedMode = _quickServiceModeOf(settings);

    return AiUiModalWrapper(
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
              )
              .animate()
              .fadeIn(duration: 300.ms, delay: 200.ms)
              .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 200.ms),
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
                    children: _quickServiceModeChoices.map((mode) {
                      final isSelected = selectedMode == mode;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _changeServiceMode(ref, mode),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: isSelected
                                  ? theme.aiUi.primaryShadow
                                  : null,
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
                                    ? Colors.white
                                    : theme.aiUi.secondaryTextColor,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 300.ms, delay: 250.ms)
              .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 250.ms),
          const SizedBox(height: 24),
          Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    _SettingTile(
                      label: t.config.enableWarp,
                      value: settings.warpConsentGiven
                          ? settings.enableWarp
                          : null,
                      icon: FluentIcons.shield_24_regular,
                      color: Colors.orange.shade400,
                      onChanged: settings.warpConsentGiven
                          ? ref
                                .read(networkSettingsProvider.notifier)
                                .setEnableWarp
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
                      color: Colors.green.shade400,
                      onChanged: ref
                          .read(networkSettingsProvider.notifier)
                          .setEnableTlsFragment,
                    ),
                    const SizedBox(height: 12),
                    _SettingTile(
                      label: t.config.allAdvancedOptions,
                      icon: FluentIcons.settings_24_regular,
                      color: Colors.blue.shade400,
                      onTap: () => _pushConfigOptions(context),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(duration: 300.ms, delay: 300.ms)
              .slideX(begin: 0.1, end: 0, duration: 300.ms, delay: 300.ms),
        ],
      ),
    );
  }

  void _pushConfigOptions(BuildContext context) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const ConfigOptionsPage()));
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.label,
    this.value,
    required this.icon,
    required this.color,
    this.onChanged,
    this.onTap,
  });

  final String label;
  final bool? value;
  final IconData icon;
  final Color color;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap ?? (onChanged != null ? () => onChanged!(!value!) : null),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.aiUi.softBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.aiUi.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (onChanged != null && value != null)
              SizedBox(
                height: 32,
                child: Switch.adaptive(
                  value: value!,
                  onChanged: onChanged,
                  activeThumbColor: theme.colorScheme.primary,
                ),
              )
            else
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: theme.aiUi.secondaryTextColor.withValues(alpha: 0.3),
              ),
          ],
        ),
      ),
    );
  }
}
