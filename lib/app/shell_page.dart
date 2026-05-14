import 'dart:io';
import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:clashmiao/features/proxy/widget/proxies_page.dart';
import 'package:clashmiao/features/settings/widget/settings_page.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  static const _pages = [
    HomePage(),
    ProxiesPage(),
    ProfilesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);
    // sing-box 核心层推过来的非致命错误 → 全局 toast。
    ref.listen<AsyncValue<BoxAlert>>(boxAlertsProvider, (_, next) {
      final alert = next.valueOrNull;
      if (alert == null) return;
      AppToast.error(context, _alertLabel(context, ref, alert));
    });

    // 桌面端预留窗口装饰（macOS 红绿灯/Win+Linux 标题栏间距），移动端交给各页面 SafeArea
    final double topPad;
    if (Platform.isMacOS) {
      topPad = 28;
    } else if (Platform.isWindows || Platform.isLinux) {
      topPad = 8;
    } else {
      topPad = 0;
    }

    final isLight = Theme.of(context).brightness == Brightness.light;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isLight
          ? Colors.white
          : const Color(0xFF16161A),
      systemNavigationBarIconBrightness: isLight
          ? Brightness.dark
          : Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        body: Column(
          children: [
            if (topPad > 0) SizedBox(height: topPad),
            Expanded(
              child: IndexedStack(index: selectedIndex, children: _pages),
            ),
            _GlassBottomNav(
              selectedIndex: selectedIndex,
              onTap: (i) =>
                  ref.read(selectedTabProvider.notifier).state = i,
            ),
          ],
        ),
      ),
    );
  }
}

String _alertLabel(BuildContext context, WidgetRef ref, BoxAlert alert) {
  final suffix = alert.message?.isNotEmpty == true ? ': ${alert.message}' : '';
  final head = switch (alert.type) {
    BoxAlertType.requestVpnPermission => 'VPN 权限被拒绝',
    BoxAlertType.requestNotificationPermission => '通知权限被拒绝',
    BoxAlertType.emptyConfiguration => '配置为空或解析失败',
    BoxAlertType.startCommandServer => 'Command Server 启动失败',
    BoxAlertType.createService => 'sing-box 创建失败',
    BoxAlertType.startService => 'sing-box 启动失败',
    BoxAlertType.unknown => '未知错误',
  };
  return '$head$suffix';
}

class _GlassBottomNav extends ConsumerWidget {
  const _GlassBottomNav({required this.selectedIndex, required this.onTap});

  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final items = [
      (
        FluentIcons.power_20_regular,
        FluentIcons.power_20_filled,
        t.home.pageTitle,
      ),
      (
        FluentIcons.filter_20_regular,
        FluentIcons.filter_20_filled,
        t.proxies.pageTitle,
      ),
      (
        FluentIcons.document_20_regular,
        FluentIcons.document_20_filled,
        t.profile.overviewPageTitle,
      ),
      (
        FluentIcons.settings_20_regular,
        FluentIcons.settings_20_filled,
        t.settings.pageTitle,
      ),
    ];
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return Container(
      decoration: BoxDecoration(
        color: isLight
            ? aiUi.glassColor
            : const Color(0xFF16161A).withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isLight ? aiUi.borderColor : const Color(0x14FFFFFF),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final (icon, selectedIcon, label) = entry.value;
          final isSelected = i == selectedIndex;

          final color = isSelected
              ? theme.colorScheme.primary
              : (isLight
                    ? aiUi.secondaryTextColor.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.4));

          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: isSelected && isLight
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF3B82F6,
                                ).withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
