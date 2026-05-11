import 'package:clashmiao/core/auto_start/auto_start_notifier.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/settings_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:io';

import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themePreferencesProvider);
    final locale = ref.watch(localePreferencesProvider);
    final t = ref.watch(translationsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              // ═══ 固定头部 ═══
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t.settings.pageTitle,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.aiUi.glassColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.aiUi.borderColor),
                      ),
                      child: Icon(
                        FluentIcons.question_circle_24_regular,
                        size: 20,
                        color: theme.aiUi.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              // ═══ 可滚动内容 ═══
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // General Section
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            iconColor: const Color(0xFF0EA5E9), // Sky Blue
                            icon: FluentIcons.globe_24_regular,
                            label: t.settings.general.locale,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _localeName(locale),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).aiUi.secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.chevron_right_24_regular,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).aiUi.secondaryTextColor,
                                ),
                              ],
                            ),
                            onTap: () => _showLocaleDialog(context, ref, t),
                          ),
                          const _Divider(),
                          _SettingsTile(
                            iconColor: const Color(0xFF8B5CF6), // Violet
                            icon: FluentIcons.dark_theme_24_regular,
                            label: t.settings.general.themeMode,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  themeMode.present(t),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).aiUi.secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.chevron_right_24_regular,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).aiUi.secondaryTextColor,
                                ),
                              ],
                            ),
                            onTap: () => _showThemeDialog(context, ref, t),
                          ),
                          if (Platform.isMacOS || Platform.isWindows) ...[
                            const _Divider(),
                            _SwitchSettingsTile(
                              iconColor: const Color(0xFF06B6D4), // Cyan
                              icon: FluentIcons.desktop_24_regular,
                              label: t.settings.general.autoStart,
                              value: ref.watch(autoStartProvider),
                              onChanged: (_) =>
                                  ref.read(autoStartProvider.notifier).toggle(),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Network Section
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            iconColor: const Color(0xFF10B981), // Emerald
                            icon: FluentIcons.plug_connected_24_regular,
                            label: t.config.mixedPort,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '2080',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).aiUi.secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.chevron_right_24_regular,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).aiUi.secondaryTextColor,
                                ),
                              ],
                            ),
                            onTap: () => _showPortEditor(context, ref, t),
                          ),
                          const _Divider(),
                          _SwitchSettingsTile(
                            iconColor: const Color(0xFFF97316), // Orange
                            icon: FluentIcons.globe_search_24_regular,
                            label: t.config.setSystemProxy,
                            value: true,
                            onChanged: (v) => AppToast.info(
                              context,
                              v
                                  ? t.settings.systemProxyEnabled
                                  : t.settings.systemProxyDisabled,
                            ),
                          ),
                          const _Divider(),
                          _SwitchSettingsTile(
                            iconColor: const Color(0xFFEC4899), // Pink
                            icon: FluentIcons.arrow_routing_24_regular,
                            label: t.config.enableTun,
                            value: false,
                            onChanged: (_) => AppToast.info(
                              context,
                              t.settings.adminPrivilegesRequired,
                            ),
                          ),
                          const _Divider(),
                          _SwitchSettingsTile(
                            iconColor: const Color(0xFF6366F1), // Indigo
                            icon: FluentIcons.wifi_1_24_regular,
                            label: t.config.allowConnectionFromLan,
                            value: false,
                            onChanged: (_) => AppToast.info(context, '开发中'),
                          ),
                        ],
                      ),
                    ),

                    // DNS Section
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            iconColor: const Color(0xFF3B82F6), // Blue
                            icon: FluentIcons.server_24_regular,
                            label: t.config.remoteDnsAddress,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'udp://1.1.1.1',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).aiUi.secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  FluentIcons.chevron_right_24_regular,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).aiUi.secondaryTextColor,
                                ),
                              ],
                            ),
                            onTap: () => AppToast.info(
                              context,
                              t.general.underDevelopment,
                            ),
                          ),
                          const _Divider(),
                          _SwitchSettingsTile(
                            iconColor: const Color(0xFF8B5CF6), // Violet
                            icon: FluentIcons.arrow_routing_24_regular,
                            label: t.config.enableDnsRouting,
                            value: true,
                            onChanged: (_) {},
                          ),
                        ],
                      ),
                    ),

                    // Advanced & Debug
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            iconColor: const Color(0xFF64748B), // Slate
                            icon: FluentIcons.document_text_24_regular,
                            label: t.logs.pageTitle,
                            trailing: Icon(
                              FluentIcons.chevron_right_24_regular,
                              size: 18,
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const _LogsPage(),
                                ),
                              );
                            },
                          ),
                          const _Divider(),
                          _SettingsTile(
                            iconColor: const Color(0xFF14B8A6), // Teal
                            icon: FluentIcons.copy_24_regular,
                            label: t.settings.exportAllOptions,
                            trailing: Icon(
                              FluentIcons.chevron_right_24_regular,
                              size: 18,
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                            onTap: () {
                              Clipboard.setData(
                                const ClipboardData(
                                  text:
                                      'ClashMiao v0.1.0\nFlutter 3.41.4\nmacOS\nCore: sing-box',
                                ),
                              );
                              AppToast.success(
                                context,
                                t.general.clipboardExportSuccessMsg,
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    // About
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : Theme.of(context).aiUi.glassColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).aiUi.borderColor.withValues(alpha: 0.05),
                        ),
                        boxShadow: Theme.of(context).aiUi.cardShadow,
                      ),
                      child: Column(
                        children: [
                          _SettingsTile(
                            iconColor: const Color(0xFFFACC15), // Yellow
                            icon: FluentIcons.info_24_regular,
                            label: '${t.about.pageTitle} ClashMiao',
                            trailing: Icon(
                              FluentIcons.chevron_right_24_regular,
                              size: 18,
                              color: Theme.of(context).aiUi.secondaryTextColor,
                            ),
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'ClashMiao',
                                applicationVersion: 'v0.1.0',
                                children: [Text(t.about.appDescription)],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _localeName(AppLocale locale) {
    if (locale == AppLocale.en) {
      return 'English';
    } else if (locale == AppLocale.zhCn) {
      return '简体中文';
    } else if (locale == AppLocale.fa) {
      return 'فارسی';
    } else if (locale == AppLocale.id) {
      return 'Indonesia';
    } else if (locale == AppLocale.zhTw) {
      return '繁體中文';
    } else if (locale == AppLocale.ru) {
      return 'Русский';
    } else if (locale == AppLocale.ptBr) {
      return 'Português (Brasil)';
    } else if (locale == AppLocale.ar) {
      return 'العربية';
    } else if (locale == AppLocale.es) {
      return 'Español';
    } else if (locale == AppLocale.tr) {
      return 'Türkçe';
    }
    return locale.languageTag;
  }

  void _showLocaleDialog(
    BuildContext context,
    WidgetRef ref,
    TranslationsEn t,
  ) {
    final icons = {
      for (var l in AppLocale.values) l: FluentIcons.local_language_24_regular,
    };
    final current = ref.read(localePreferencesProvider);

    showAiUiModal(
      context: context,
      builder: (ctx) {
        return SettingsSelectionModal<AppLocale>(
          title: t.settings.general.locale,
          items: AppLocale.values,
          selectedItem: current,
          itemIcon: (item) => icons[item]!,
          itemLabel: (item) => _localeName(item),
          onSelected: (item) {
            ref.read(localePreferencesProvider.notifier).changeLocale(item);
          },
        );
      },
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref, TranslationsEn t) {
    final icons = {
      AppThemeMode.system: FluentIcons.device_eq_24_regular,
      AppThemeMode.light: FluentIcons.weather_sunny_24_regular,
      AppThemeMode.dark: FluentIcons.weather_moon_24_regular,
    };
    final current = ref.read(themePreferencesProvider);

    showAiUiModal(
      context: context,
      builder: (ctx) {
        return SettingsSelectionModal<AppThemeMode>(
          title: t.settings.general.themeMode,
          items: AppThemeMode.values,
          selectedItem: current,
          itemIcon: (item) => icons[item]!,
          itemLabel: (item) => item.present(t),
          onSelected: (item) {
            ref.read(themePreferencesProvider.notifier).changeThemeMode(item);
          },
        );
      },
    );
  }

  void _showPortEditor(BuildContext context, WidgetRef ref, TranslationsEn t) {
    final controller = TextEditingController(text: '2080');
    showAiUiModal(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return AiUiModalWrapper(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.config.mixedPort,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t.config.mixedPort,
                    hintText: '1024-65535',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(
                      FluentIcons.plug_connected_24_regular,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      AppToast.info(context, t.settings.portChangeNotice);
                    },
                    child: Text(t.general.confirm),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).aiUi.borderColor.withValues(alpha: 0.05),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (iconColor ?? Theme.of(context).aiUi.secondaryTextColor)
                    .withValues(alpha: isLight ? 0.1 : 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor ?? Theme.of(context).aiUi.secondaryTextColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SwitchSettingsTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSettingsTile({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: icon,
      iconColor: iconColor,
      label: label,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Theme.of(context).colorScheme.primary,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// 日志页
class _LogsPage extends ConsumerWidget {
  const _LogsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isConnected =
        ref.watch(connectionControllerProvider).valueOrNull is BoxStarted;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.logs.pageTitle),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.delete_24_regular),
            onPressed: () {
              AppToast.info(context, t.logs.logsCleared);
            },
          ),
          IconButton(
            icon: const Icon(FluentIcons.copy_24_regular),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: ''));
              AppToast.success(context, t.logs.logsCopied);
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isConnected
                  ? FluentIcons.document_text_24_regular
                  : FluentIcons.plug_disconnected_24_regular,
              size: 48,
              color: aiUi.secondaryTextColor,
            ),
            const SizedBox(height: 16),
            Text(
              isConnected
                  ? t.logs.logsUnderDevelopment
                  : t.logs.noLogsWhenDisconnected,
              style: TextStyle(fontSize: 14, color: aiUi.secondaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
