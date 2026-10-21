import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/auto_start/auto_start_notifier.dart';
import 'package:clashmiao/core/auto_start_permission/auto_start_permission_service.dart';
import 'package:clashmiao/core/battery_optimization/battery_optimization_service.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/settings/application/setting_toggles.dart';
import 'package:clashmiao/features/settings/presentation/per_app_proxy_page.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/settings_row.dart';
import 'package:clashmiao/shared/components/settings_selection_modal.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'dart:io';

import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';

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

    // 背景晕染统一由 ShellPage 底下那层 BrandBackdrop 画，页面自己保持透明。
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                    Text(
                      t.settings.pageTitle,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
              // 三组：通用 / 连接 / 隐私。组间 24 dp，组标题到卡片 8 dp。
              // 图标不再各染一色——彩虹色会让「绿/橙/红」失去状态含义，
              // 统一用中性的次要文字色（见 _SettingsTile）。
              SliverList.list(
                children: [
                  _SettingsGroup(
                    title: t.settings.groups.general,
                    children: [
                      _SettingsTile(
                        icon: FluentIcons.globe_24_regular,
                        label: t.settings.general.locale,
                        trailing: _TrailingValue(value: _localeName(locale)),
                        onTap: () => _showLocaleDialog(context, ref, t),
                      ),
                      _SettingsTile(
                        icon: FluentIcons.dark_theme_24_regular,
                        label: t.settings.general.themeMode,
                        trailing: _TrailingValue(value: themeMode.present(t)),
                        onTap: () => _showThemeDialog(context, ref, t),
                      ),
                      if (isAndroid)
                        _BoolPreferenceTile(
                          icon: FluentIcons.phone_vibrate_24_regular,
                          label: t.settings.general.hapticFeedback,
                          prefKey: 'clashmiao_haptic_feedback',
                          defaultValue: true,
                        ),
                      if (Platform.isMacOS || Platform.isWindows) ...[
                        _SwitchSettingsTile(
                          icon: FluentIcons.desktop_24_regular,
                          label: t.settings.general.autoStart,
                          value: ref.watch(autoStartProvider),
                          onChanged: (_) =>
                              ref.read(autoStartProvider.notifier).toggle(),
                        ),
                        _BoolPreferenceTile(
                          icon: FluentIcons.eye_off_24_regular,
                          label: t.settings.general.silentStart,
                          prefKey: 'clashmiao_silent_start',
                          defaultValue: false,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SettingsGroup(
                    title: t.settings.groups.connection,
                    children: [
                      _BoolPreferenceTile(
                        icon: FluentIcons.globe_search_24_regular,
                        label: t.settings.general.autoIpCheck,
                        prefKey: 'clashmiao_auto_ip_check',
                        defaultValue: true,
                      ),
                      if (isAndroid) ...[
                        _BoolPreferenceTile(
                          icon: FluentIcons.top_speed_24_regular,
                          label: t.settings.general.dynamicNotification,
                          prefKey: 'dynamic_notification',
                          defaultValue: true,
                        ),
                        _BatteryOptimizationTile(
                          label: t.settings.general.ignoreBatteryOptimizations,
                          subtitle:
                              t.settings.general.ignoreBatteryOptimizationsMsg,
                        ),
                        // 仅 MIUI / HyperOS 才会渲染（其它系统整行不出现，连分隔线都没有）。
                        _MiuiAutoStartTile(
                          label: t.settings.general.autoStartPermission,
                          subtitle: t.settings.general.autoStartPermissionMsg,
                        ),
                        _SettingsTile(
                          icon: FluentIcons.phone_tablet_24_regular,
                          label: t.settings.network.perAppProxyPageTitle,
                          trailing: const _Chevron(),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PerAppProxyPage(),
                            ),
                          ),
                        ),
                      ],
                      if (isIOS)
                        _SettingsTile(
                          icon: FluentIcons.arrow_reset_24_regular,
                          label: t.settings.advanced.resetTunnel,
                          trailing: const _Chevron(),
                          onTap: () => _resetTunnel(context, ref, t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _SettingsGroup(
                    title: t.settings.groups.privacy,
                    children: [
                      _AnalyticsToggle(
                        label: t.settings.general.enableAnalytics,
                      ),
                    ],
                  ),
                ],
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
      useRootNavigator: true,
      isScrollControlled: true,
      sheetAnimationStyle: Motion.sheetAnimation(context),
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
      useRootNavigator: true,
      isScrollControlled: true,
      sheetAnimationStyle: Motion.sheetAnimation(context),
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
  ///
  /// 成功也要给 toast。这里原本只在失败时提示，理由是"成功与否用户自己能
  /// 感知到隧道是否恢复"——但这个理由站不住：重置是瞬时的，设置页上没有任何
  /// 可见状态跟着变，用户点完看到的就是**什么都没发生**，无法区分"成功了"
  /// 和"这个按钮是坏的"。项目其它地方的一次性动作（导出、复制、生成 WARP
  /// 配置）成功时都有 toast，这里不该例外。
  Future<void> _resetTunnel(
    BuildContext context,
    WidgetRef ref,
    TranslationsEn t,
  ) async {
    try {
      await ref.read(boxServiceProvider).resetTunnel();
      if (context.mounted) {
        AppToast.success(context, t.settings.advanced.resetTunnelSuccess);
      }
    } catch (e, st) {
      // 技术细节只进日志，界面只给本地化文案。
      logAppFailure('settings.resetTunnel', e, st);
      if (context.mounted) {
        AppToast.error(context, t.failure.unexpected);
      }
    }
  }
}

/// 一组设置：组标题 + 一张卡片，卡片内行与行之间画分隔线。
///
/// 组标题 13 sp / w500，到卡片 8 dp。标题标成 header 语义，读屏可按标题跳组。
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final child in children) {
      // 自带分隔线的行（可能整行不渲染）自己决定要不要画前导分隔线，
      // 否则它藏起来时会留下一条多余的线。
      if (rows.isNotEmpty && child is! _OwnsLeadingDivider) {
        rows.add(const _Divider());
      }
      rows.add(child);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            header: true,
            container: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).aiUi.secondaryTextColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _BoolPreferenceTile extends ConsumerWidget {
  const _BoolPreferenceTile({
    required this.icon,
    required this.label,
    required this.prefKey,
    required this.defaultValue,
  });

  final IconData icon;
  final String label;
  final String prefKey;
  final bool defaultValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = (key: prefKey, defaultValue: defaultValue);
    final value = ref.watch(boolPreferenceProvider(spec));
    return _SwitchSettingsTile(
      icon: icon,
      label: label,
      value: value,
      onChanged: (next) =>
          ref.read(boolPreferenceProvider(spec).notifier).update(next),
    );
  }
}

/// 电池优化豁免入口（仅 Android）。
///
/// 点击弹系统对话框（`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`），返回后
/// 重新查询一次豁免状态以刷新 tile 上的状态文案。这两个原生方法没有走
/// Pigeon，走的是裸 `MethodChannel('com.clashmiao.app/platform')`
/// （见 [BatteryOptimizationService]），此处只负责 UI 展示与刷新时机。
/// Analytics 开关：读写逻辑跟改动前完全一致（同一个 `boolPreferenceProvider`
/// family、同一个 `clashmiao_analytics_enabled` key、同一个默认值 false），只是
/// 渲染使用共享的 [AnalyticsToggleTile]。
class _AnalyticsToggle extends ConsumerWidget {
  const _AnalyticsToggle({required this.label});

  final String label;

  static const _spec = (
    key: 'clashmiao_analytics_enabled',
    defaultValue: false,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(boolPreferenceProvider(_spec));
    return AnalyticsToggleTile(
      label: label,
      value: value,
      onChanged: (next) =>
          ref.read(boolPreferenceProvider(_spec).notifier).update(next),
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

  /// 防重入：一次请求在飞的时候再点没有意义（系统同时只可能弹一个豁免对话框），
  /// 原生侧对重复请求也只会直接回 false。挡在这里可以让用户连点不产生任何
  /// 多余的往返，也不会用一个 false 结果去覆盖真实状态。
  bool _requesting = false;

  Future<void> _onTap() async {
    if (_requesting) return;
    _requesting = true;
    try {
      await ref
          .read(batteryOptimizationServiceProvider)
          .requestIgnoreBatteryOptimizations();
    } finally {
      _requesting = false;
    }
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

/// 标记接口：实现它的行自己负责前导分隔线，[_SettingsGroup] 不再替它补。
abstract interface class _OwnsLeadingDivider {}

/// MIUI / HyperOS「自启动」权限入口（仅 Android 段内、且仅这两个系统上才会渲染）。
///
/// MIUI 会在开机、应用更新的广播派发阶段就拦掉被禁止自启动的应用，进程都起不来，
/// 持久化的 VPN 意图也就无从恢复。这里如实展示当前开关状态，点击跳系统的自启动管理页。
/// 非 MIUI（状态为 unsupported）时整行不渲染——不给用户摆点了没用的选项。
///
/// 用户在系统设置里改完返回时（[AppLifecycleState.resumed]）重新查询，状态文案才会跟上；
/// 重新查询期间保留旧值，不闪回占位符。
class _MiuiAutoStartTile extends ConsumerStatefulWidget
    implements _OwnsLeadingDivider {
  const _MiuiAutoStartTile({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  ConsumerState<_MiuiAutoStartTile> createState() => _MiuiAutoStartTileState();
}

class _MiuiAutoStartTileState extends ConsumerState<_MiuiAutoStartTile>
    with WidgetsBindingObserver {
  /// null 表示首次查询还没返回。
  MiuiAutoStartStatus? _status;

  /// 查询代数：连续触发多次查询时，只认最新一次的结果，晚到的旧结果直接丢弃。
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    final status = await ref.read(autoStartPermissionServiceProvider).status();
    if (!mounted || generation != _generation) return;
    setState(() => _status = status);
  }

  Future<void> _onTap() async {
    await ref.read(autoStartPermissionServiceProvider).openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    // 首次查询返回前也不渲染：非 MIUI 的 Android 上不能先闪出一行再消失。
    if (status == null || status == MiuiAutoStartStatus.unsupported) {
      return const SizedBox.shrink();
    }
    final texts = ref.watch(translationsProvider).settings.general;
    final statusText = switch (status) {
      MiuiAutoStartStatus.allowed => texts.autoStartPermissionStatus.allowed,
      MiuiAutoStartStatus.denied => texts.autoStartPermissionStatus.denied,
      MiuiAutoStartStatus.unknown => texts.autoStartPermissionStatus.unknown,
      MiuiAutoStartStatus.unsupported => '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Divider(),
        _SettingsTile(
          icon: FluentIcons.power_24_regular,
          label: widget.label,
          subtitle: widget.subtitle,
          trailing: _TrailingValue(value: statusText),
          onTap: _onTap,
        ),
      ],
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

class _TrailingValue extends StatelessWidget {
  const _TrailingValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    // 当前值最多占屏宽三成：文字放大或语言名很长（如「Português (Brasil)」）时
    // 在这个宽度内换行，而不是把左边的标题挤到零宽、右边溢出。
    final maxValueWidth = MediaQuery.sizeOf(context).width * 0.32;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxValueWidth),
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).aiUi.secondaryTextColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const _Chevron(),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) {
    return Icon(
      FluentIcons.chevron_right_24_regular,
      size: 18,
      color: Theme.of(context).aiUi.secondaryTextColor,
    );
  }
}

/// 设置行：高度至少 [kSettingsRowMinHeight]，文案变长或字号放大时自然长高。
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// 可选副标题，用于展示补充说明（例如电池优化豁免入口的效果说明）。
  final String? subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  /// trailing 自己就是可操作控件（开关）时为 true：行上的 InkWell 不再生成
  /// 自己的点击语义，整行合并后只剩开关那一个操作，不会出现两个可点节点。
  final bool trailingOwnsAction;

  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.trailing,
    this.onTap,
    this.trailingOwnsAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).aiUi.secondaryTextColor;
    final labelColumn = subtitle == null
        // 上下各 4 dp：开关行的行高由 48 dp 的开关撑起（4+48+4=56），文字
        // 换行时仍有留白。
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
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
              Text(subtitle!, style: TextStyle(fontSize: 12, color: secondary)),
            ],
          );

    // MergeSemantics：整行是一个语义节点（标题 + 状态/当前值 + 单一操作），
    // 读屏不会把图标、标题、开关拆成几个各自可点的节点。
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        excludeFromSemantics: trailingOwnsAction,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kSettingsRowMinHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: subtitle == null ? 4 : 12,
            ),
            child: Row(
              children: [
                // 图标不染色：设置页不再是彩虹，绿/橙/红留给状态。
                ExcludeSemantics(child: Icon(icon, size: 20, color: secondary)),
                const SizedBox(width: 16),
                Expanded(child: labelColumn),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchSettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: icon,
      label: label,
      // 开关保持 Material 默认的 48 dp 点击目标，不 shrinkWrap。
      trailing: Switch(value: value, onChanged: onChanged),
      trailingOwnsAction: true,
      onTap: () => onChanged(!value),
    );
  }
}
