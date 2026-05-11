import 'dart:io';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:clashmiao/features/proxy/widget/proxies_page.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:clashmiao/features/settings/widget/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  int _selectedIndex = 0;

  static const _pages = [
    HomePage(),
    ProxiesPage(),
    ProfilesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // 统一顶部偏移：macOS 避开红绿灯，桌面端预留间距，移动端用系统安全区
    final double topPad;
    if (Platform.isMacOS) {
      topPad = 28;
    } else if (Platform.isWindows || Platform.isLinux) {
      topPad = 8;
    } else {
      topPad = MediaQuery.of(context).padding.top;
    }

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: topPad),
          Expanded(
            child: IndexedStack(index: _selectedIndex, children: _pages),
          ),
          _GlassBottomNav(
            selectedIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
          ),
        ],
      ),
    );
  }
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
        t.home.pageTitle
      ),
      (
        FluentIcons.filter_20_regular,
        FluentIcons.filter_20_filled,
        t.proxies.pageTitle
      ),
      (
        FluentIcons.document_20_regular,
        FluentIcons.document_20_filled,
        t.profile.overviewPageTitle
      ),
      (
        FluentIcons.settings_20_regular,
        FluentIcons.settings_20_filled,
        t.settings.pageTitle
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
