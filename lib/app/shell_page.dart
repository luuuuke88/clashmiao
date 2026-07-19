import 'dart:io';
import 'dart:ui';
import 'package:clashmiao/app/state/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/box_alert.dart';
import 'package:clashmiao/core/model/connection_error_classifier.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/about/widget/about_page.dart';
import 'package:clashmiao/features/assets/widget/assets_page.dart';
import 'package:clashmiao/features/config/widget/config_options_page.dart';
import 'package:clashmiao/features/home/widget/quick_settings_modal.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:clashmiao/features/import/qr_scanner_page.dart';
import 'package:clashmiao/features/logs/widget/logs_page.dart';
import 'package:clashmiao/features/profile/widget/profile_details_page.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:clashmiao/features/settings/widget/settings_page.dart';
import 'package:clashmiao/features/settings/widget/per_app_proxy_page.dart';
import 'package:clashmiao/features/proxy/widget/proxies_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/blocking_alert_dialog.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
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
  bool _debugAddProfileOpened = false;
  bool _deepLinkResultChecked = false;

  static const _pages = [
    HomePage(),
    ProxiesPage(
      debugOpenProxyNameModal: bool.fromEnvironment(
        'CLASHMIAO_OPEN_PROXY_NAME_MODAL',
      ),
    ),
    SettingsPage(),
    AboutPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_ADD_PROFILE') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showProfileFormDialog(context, ref);
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_MANUAL_PROFILE') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showProfileManualFormDialog(context, ref);
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_PROFILES') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAiUiModal(
          context: context,
          builder: (_) => const ProfilesPage(
            embedInSheet: true,
            debugOpenSortModal: bool.fromEnvironment(
              'CLASHMIAO_OPEN_PROFILE_SORT',
            ),
            debugOpenActionsModal: bool.fromEnvironment(
              'CLASHMIAO_OPEN_PROFILE_ACTIONS',
            ),
          ),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_PROFILE_DETAILS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        const profileId =
            bool.fromEnvironment('CLASHMIAO_OPEN_PROFILE_DETAILS_NO_SUBINFO')
            ? 'debug-profile-no-subinfo'
            : 'debug-home-profile';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ProfileDetailsPage(
              profileId,
              debugOpenUpdateInterval: bool.fromEnvironment(
                'CLASHMIAO_OPEN_PROFILE_UPDATE_INTERVAL',
              ),
            ),
          ),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_QUICK_SETTINGS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAiUiModal(
          context: context,
          builder: (_) => const QuickSettingsModal(),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_LOGS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const LogsPage()));
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_CONFIG_OPTIONS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ConfigOptionsPage(
              debugOpenActions: bool.fromEnvironment(
                'CLASHMIAO_OPEN_CONFIG_ACTIONS',
              ),
              debugOpenMixedPortInput: bool.fromEnvironment(
                'CLASHMIAO_OPEN_CONFIG_MIXED_PORT_INPUT',
              ),
              debugOpenUrlTestIntervalSlider: bool.fromEnvironment(
                'CLASHMIAO_OPEN_CONFIG_URL_TEST_INTERVAL_SLIDER',
              ),
              debugOpenWarpConsent: bool.fromEnvironment(
                'CLASHMIAO_OPEN_CONFIG_WARP_CONSENT',
              ),
              debugInitialScrollOffset: int.fromEnvironment(
                'CLASHMIAO_OPEN_CONFIG_SCROLL_OFFSET',
              ),
            ),
          ),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_ASSETS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AssetsPage()));
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_PER_APP_PROXY') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PerAppProxyPage()));
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_QR_SCANNER_DENIED') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const QrScannerPage.permissionDeniedPreview(),
          ),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_CONFIRMATION_DIALOG') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final t = ref.read(translationsProvider);
        showConfirmationDialog(
          context,
          title: t.profile.delete.buttonTxt,
          message: t.profile.delete.confirmationMsg,
          icon: FluentIcons.delete_24_regular,
        );
      });
    }

    // sing-box 核心层推过来的 alert：内核压根没起来（isFatal）用阻断式弹窗
    // ——必须点确认，不能被用户划走错过；其余（权限请求等，用户仍可重试/
    // 手动处理）维持非阻断 toast。文案统一走 classifyBoxAlertMessage，跟
    // ConnectionController 写 connectionErrorProvider 用的是同一份分类器，
    // 不再各自维护一份（此前这里是硬编码中文 _alertLabel，跟分类器脱节）。
    ref.listen<AsyncValue<BoxAlert>>(boxAlertsProvider, (_, next) {
      final alert = next.valueOrNull;
      if (alert == null) return;
      final t = ref.read(translationsProvider);
      final message = classifyBoxAlertMessage(alert, t);
      if (alert.type.isFatal) {
        showBlockingAlert(
          context,
          title: t.home.connectionFailedTitle,
          message: message,
          icon: FluentIcons.error_circle_24_regular,
        );
        return;
      }
      AppToast.error(context, message);
    });

    // 深链导入结果（DeepLinkService 解析 URI 并调用 addByUrl/addByContent
    // 后写入）→ 全局 toast。
    //
    // `WidgetRef.listen`（build 内安全的那个重载）不支持 fireImmediately，
    // 所以冷启动场景下"深链解析先于 ShellPage 挂载完成"这个时序用同一个文件
    // 已有的"只在首次 build 检查一次"写法兜底：读一次当前值，如果已经有
    // 一个结果在等着（说明 DeepLinkService 抢在 ShellPage 挂载完之前就处理
    // 完了），postFrameCallback 里补展示一次；之后的变化交给下面的
    // ref.listen 正常处理。
    if (!_deepLinkResultChecked) {
      _deepLinkResultChecked = true;
      final pendingDeepLinkResult = ref.read(deepLinkImportResultProvider);
      if (pendingDeepLinkResult != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _handleDeepLinkResult(context, ref, pendingDeepLinkResult);
          }
        });
      }
    }
    ref.listen<DeepLinkImportResult?>(deepLinkImportResultProvider, (_, next) {
      if (next != null) _handleDeepLinkResult(context, ref, next);
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
        extendBody: true,
        body: Column(
          children: [
            if (topPad > 0) SizedBox(height: topPad),
            Expanded(
              child: IndexedStack(index: selectedIndex, children: _pages),
            ),
          ],
        ),
        bottomNavigationBar: _GlassBottomNav(
          selectedIndex: selectedIndex,
          onTap: (i) => ref.read(selectedTabProvider.notifier).state = i,
        ),
      ),
    );
  }
}

/// 展示一条深链导入结果的 toast，并把 [deepLinkImportResultProvider] 的
/// state 重置回 `null`——建模成"一次性事件"，避免 ShellPage 重建时把同一条
/// 结果再弹一次。
void _handleDeepLinkResult(
  BuildContext context,
  WidgetRef ref,
  DeepLinkImportResult result,
) {
  switch (result) {
    case DeepLinkImportSuccess(:final profileName):
      AppToast.success(context, '已导入订阅：$profileName');
    case DeepLinkImportFailure(:final message):
      AppToast.error(context, '导入订阅失败：$message');
  }
  ref.read(deepLinkImportResultProvider.notifier).state = null;
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
        FluentIcons.settings_20_regular,
        FluentIcons.settings_20_filled,
        t.settings.pageTitle,
      ),
      (
        FluentIcons.info_20_regular,
        FluentIcons.info_20_filled,
        t.about.pageTitle,
      ),
    ];
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isLight
                ? aiUi.glassColor
                : const Color(0xFF16161A).withValues(alpha: 0.8),
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
                  key: ValueKey('bottom_nav_$i'),
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
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                )
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
        ),
      ),
    );
  }
}
