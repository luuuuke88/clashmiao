import 'package:clashmiao/core/auto_start/auto_start_notifier.dart';
import 'package:clashmiao/core/battery_optimization/battery_optimization_service.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/settings/widget/per_app_proxy_page.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/settings_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:io';

import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _boolPreferenceProvider = StateNotifierProvider.autoDispose
    .family<_BoolPreferenceNotifier, bool, ({bool defaultValue, String key})>((
      ref,
      spec,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return _BoolPreferenceNotifier(prefs, spec.key, spec.defaultValue);
    });

class _BoolPreferenceNotifier extends StateNotifier<bool> {
  _BoolPreferenceNotifier(this._prefs, this._key, bool defaultValue)
    : super(_prefs.getBool(_key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String _key;

  Future<void> update(bool value) async {
    state = value;
    await _prefs.setBool(_key, value);
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.debugIsAndroid, this.debugIsIOS});

  /// 仅供测试注入：覆盖 [Platform.isAndroid] 判断结果。生产环境不传（为
  /// null）时使用真实 [Platform.isAndroid]，行为与改动前完全一致。
  /// 存在原因：`flutter test` 宿主 Dart VM 的 `dart:io Platform.isAndroid`
  /// 反映宿主机 OS，在非 Android 开发机上恒为 false，Android-only 分支
  /// 在 widget test 层面本来不可达，需要这个测试专用逃生口。
  final bool? debugIsAndroid;

  /// 仅供测试注入：覆盖 [Platform.isIOS] 判断结果，原因跟 [debugIsAndroid]
  /// 完全一样——`flutter test` 宿主机不是 iOS，iOS-only 的 Reset Tunnel 入口
  /// 在没有这个逃生口时永远测不到。
  final bool? debugIsIOS;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _debugModalOpened = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themePreferencesProvider);
    final locale = ref.watch(localePreferencesProvider);
    final t = ref.watch(translationsProvider);
    final isAndroid = widget.debugIsAndroid ?? Platform.isAndroid;
    final isIOS = widget.debugIsIOS ?? Platform.isIOS;

    if (!_debugModalOpened &&
        (const bool.fromEnvironment('CLASHMIAO_OPEN_SETTINGS_LOCALE') ||
            const bool.fromEnvironment('CLASHMIAO_OPEN_SETTINGS_THEME'))) {
      _debugModalOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (const bool.fromEnvironment('CLASHMIAO_OPEN_SETTINGS_THEME')) {
          _showThemeDialog(context, ref, t);
        } else {
          _showLocaleDialog(context, ref, t);
        }
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    Row(
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
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 24),
                  decoration: _settingsCardDecoration(context),
                  child: Column(
                    children: [
                      _SettingsTile(
                        iconColor: const Color(0xFF0EA5E9),
                        icon: FluentIcons.globe_24_regular,
                        label: t.settings.general.locale,
                        trailing: _TrailingValue(value: _localeName(locale)),
                        onTap: () => _showLocaleDialog(context, ref, t),
                      ),
                      const _Divider(),
                      _SettingsTile(
                        iconColor: const Color(0xFF8B5CF6),
                        icon: FluentIcons.dark_theme_24_regular,
                        label: t.settings.general.themeMode,
                        trailing: _TrailingValue(value: themeMode.present(t)),
                        onTap: () => _showThemeDialog(context, ref, t),
                      ),
                      const _Divider(),
                      _AnalyticsToggle(
                        label: t.settings.general.enableAnalytics,
                      ),
                      const _Divider(),
                      _BoolPreferenceTile(
                        iconColor: const Color(0xFF10B981),
                        icon: FluentIcons.globe_search_24_regular,
                        label: t.settings.general.autoIpCheck,
                        prefKey: 'clashmiao_auto_ip_check',
                        defaultValue: true,
                      ),
                      if (isAndroid) ...[
                        const _Divider(),
                        _BoolPreferenceTile(
                          iconColor: const Color(0xFFEC4899),
                          icon: FluentIcons.top_speed_24_regular,
                          label: t.settings.general.dynamicNotification,
                          prefKey: 'dynamic_notification',
                          defaultValue: true,
                        ),
                        const _Divider(),
                        _BoolPreferenceTile(
                          iconColor: const Color(0xFF6366F1),
                          icon: FluentIcons.phone_vibrate_24_regular,
                          label: t.settings.general.hapticFeedback,
                          prefKey: 'clashmiao_haptic_feedback',
                          defaultValue: true,
                        ),
                        const _Divider(),
                        _BatteryOptimizationTile(
                          label: t.settings.general.ignoreBatteryOptimizations,
                          subtitle:
                              t.settings.general.ignoreBatteryOptimizationsMsg,
                        ),
                        const _Divider(),
                        _SettingsTile(
                          iconColor: const Color(0xFF059669),
                          icon: FluentIcons.phone_tablet_24_regular,
                          label: t.settings.network.perAppProxyPageTitle,
                          trailing: _Chevron(),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PerAppProxyPage(),
                            ),
                          ),
                        ),
                      ],
                      if (Platform.isMacOS || Platform.isWindows) ...[
                        const _Divider(),
                        _SwitchSettingsTile(
                          iconColor: const Color(0xFF06B6D4),
                          icon: FluentIcons.desktop_24_regular,
                          label: t.settings.general.autoStart,
                          value: ref.watch(autoStartProvider),
                          onChanged: (_) =>
                              ref.read(autoStartProvider.notifier).toggle(),
                        ),
                        const _Divider(),
                        _BoolPreferenceTile(
                          iconColor: const Color(0xFF64748B),
                          icon: FluentIcons.eye_off_24_regular,
                          label: t.settings.general.silentStart,
                          prefKey: 'clashmiao_silent_start',
                          defaultValue: false,
                        ),
                      ],
                      if (isIOS) ...[
                        const _Divider(),
                        _SettingsTile(
                          iconColor: const Color(0xFFEF4444),
                          icon: FluentIcons.arrow_reset_24_regular,
                          label: t.settings.advanced.resetTunnel,
                          trailing: _Chevron(),
                          onTap: () => _resetTunnel(context, ref, t),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
    final current = ref.read(localePreferencesProvider);

    showModalBottomSheet<AppLocale>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => SettingsSelectionModal<AppLocale>(
        title: t.settings.general.locale,
        items: AppLocale.values,
        selectedItem: current,
        itemLabel: (item) => _localeName(item),
        onSelected: (item) {
          ref.read(localePreferencesProvider.notifier).changeLocale(item);
        },
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref, TranslationsEn t) {
    final icons = {
      AppThemeMode.system: FluentIcons.settings_24_regular,
      AppThemeMode.light: FluentIcons.weather_sunny_24_regular,
      AppThemeMode.dark: FluentIcons.weather_moon_24_regular,
    };
    final current = ref.read(themePreferencesProvider);

    showModalBottomSheet<AppThemeMode>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => SettingsSelectionModal<AppThemeMode>(
        title: t.settings.general.themeMode,
        items: AppThemeMode.values,
        selectedItem: current,
        itemIcon: (item) => icons[item]!,
        itemLabel: (item) => item.present(t),
        onSelected: (item) {
          ref.read(themePreferencesProvider.notifier).changeThemeMode(item);
        },
      ),
    );
  }

  /// iOS 专用：强制重置隧道（取消用户主动断开标记，触发重连）。
  /// 后端 `resetTunnel` 早已接好（[BoxService.resetTunnel] /
  /// `platform_box_service.dart`），此前没有任何页面提供入口。跟其它设置项
  /// 的即时反馈不同，这里没有持久化状态可展示，失败时用 toast 报错，避免
  /// 静默吞掉——成功与否用户自己能感知到隧道是否恢复，不需要额外的成功提示。
  Future<void> _resetTunnel(
    BuildContext context,
    WidgetRef ref,
    TranslationsEn t,
  ) async {
    try {
      await ref.read(boxServiceProvider).resetTunnel();
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, '${t.failure.unexpected}: $e');
      }
    }
  }
}

class _BoolPreferenceTile extends ConsumerWidget {
  const _BoolPreferenceTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.prefKey,
    required this.defaultValue,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String prefKey;
  final bool defaultValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = (key: prefKey, defaultValue: defaultValue);
    final value = ref.watch(_boolPreferenceProvider(spec));
    return _SwitchSettingsTile(
      icon: icon,
      iconColor: iconColor,
      label: label,
      value: value,
      onChanged: (next) =>
          ref.read(_boolPreferenceProvider(spec).notifier).update(next),
    );
  }
}

/// 电池优化豁免入口（仅 Android）。
///
/// 点击弹系统对话框（`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`），返回后
/// 重新查询一次豁免状态以刷新 tile 上的状态文案。这两个原生方法没有走
/// Pigeon，走的是裸 `MethodChannel('com.clashmiao.app/platform')`
/// （见 [BatteryOptimizationService]），此处只负责 UI 展示与刷新时机。
/// Analytics 开关：读写逻辑跟改动前完全一致（同一个 `_boolPreferenceProvider`
/// family、同一个 `clashmiao_analytics_enabled` key、同一个默认值 false），只是
/// 渲染换成共享的 [AnalyticsToggleTile]——见该组件文档，统一后的样式是项目里
/// "设置项 + 开关"占主导地位的单行样式，跟 `onboarding_page.dart` 之前私有的
/// 卡片样式 `_IntroSwitchTile` 收敛成同一份实现。
class _AnalyticsToggle extends ConsumerWidget {
  const _AnalyticsToggle({required this.label});

  final String label;

  static const _spec = (
    key: 'clashmiao_analytics_enabled',
    defaultValue: false,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_boolPreferenceProvider(_spec));
    return AnalyticsToggleTile(
      label: label,
      value: value,
      onChanged: (next) =>
          ref.read(_boolPreferenceProvider(_spec).notifier).update(next),
    );
  }
}

class _BatteryOptimizationTile extends ConsumerStatefulWidget {
  const _BatteryOptimizationTile({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  ConsumerState<_BatteryOptimizationTile> createState() =>
      _BatteryOptimizationTileState();
}

class _BatteryOptimizationTileState
    extends ConsumerState<_BatteryOptimizationTile> {
  late Future<bool> _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = _queryStatus();
  }

  Future<bool> _queryStatus() {
    return ref
        .read(batteryOptimizationServiceProvider)
        .isIgnoringBatteryOptimizations();
  }

  Future<void> _onTap() async {
    await ref
        .read(batteryOptimizationServiceProvider)
        .requestIgnoreBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _statusFuture = _queryStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    return FutureBuilder<bool>(
      future: _statusFuture,
      builder: (context, snapshot) {
        final exempted = snapshot.data ?? false;
        final status = t.settings.general.batteryOptimizationStatus;
        // 查询结果到达前用一个占位符号，避免闪一下"未豁免"再跳"已豁免"。
        final statusText = snapshot.connectionState == ConnectionState.waiting
            ? status.pending
            : (exempted ? status.exempted : status.notExempted);
        return _SettingsTile(
          iconColor: const Color(0xFF22C55E),
          icon: FluentIcons.battery_checkmark_24_regular,
          label: widget.label,
          subtitle: widget.subtitle,
          trailing: _TrailingValue(value: statusText),
          onTap: _onTap,
        );
      },
    );
  }
}

BoxDecoration _settingsCardDecoration(BuildContext context) {
  return BoxDecoration(
    color: Theme.of(context).brightness == Brightness.light
        ? Colors.white
        : Theme.of(context).aiUi.glassColor,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Theme.of(context).aiUi.borderColor.withValues(alpha: 0.05),
    ),
    boxShadow: Theme.of(context).aiUi.cardShadow,
  );
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

class _TrailingValue extends StatelessWidget {
  const _TrailingValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).aiUi.secondaryTextColor,
          ),
        ),
        const SizedBox(width: 8),
        _Chevron(),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(
      FluentIcons.chevron_right_24_regular,
      size: 18,
      color: Theme.of(context).aiUi.secondaryTextColor,
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// 可选副标题，用于展示补充说明（例如电池优化豁免入口的效果说明）。
  /// 为 null 时布局与改动前完全一致（单行、固定 56 高）。
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  final Color? iconColor;

  const _SettingsTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final labelColumn = subtitle == null
        ? Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          )
        : Column(
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
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).aiUi.secondaryTextColor,
                ),
              ),
            ],
          );

    return InkWell(
      onTap: onTap,
      child: Container(
        height: subtitle == null ? 56 : null,
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: subtitle == null ? 0 : 12,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: iconColor ?? Theme.of(context).aiUi.secondaryTextColor,
            ),
            const SizedBox(width: 16),
            Expanded(child: labelColumn),
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
