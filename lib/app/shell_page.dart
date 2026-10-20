import 'dart:io';
import 'dart:math' as math;

import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/app/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/domain/connection/application/connection_error_classifier.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/about/presentation/about_page.dart';
import 'package:clashmiao/features/assets/presentation/assets_page.dart';
import 'package:clashmiao/features/config/presentation/config_options_page.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/features/profile/presentation/qr_scanner_page.dart';
import 'package:clashmiao/features/logs/presentation/logs_page.dart';
import 'package:clashmiao/features/profile/presentation/profile_details_page.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:clashmiao/features/settings/presentation/settings_page.dart';
import 'package:clashmiao/features/settings/presentation/per_app_proxy_page.dart';
import 'package:clashmiao/features/proxy/presentation/proxies_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/blocking_alert_dialog.dart';
import 'package:clashmiao/shared/components/brand_backdrop.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/app/restore_recovery_notice.dart';
import 'package:clashmiao/features/config/application/startup_restore_notice.dart';

class ShellPage extends ConsumerStatefulWidget {
  const ShellPage({super.key});

  @override
  ConsumerState<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends ConsumerState<ShellPage> {
  bool _debugAddProfileOpened = false;
  bool _deepLinkResultChecked = false;
  bool _staleProxyNoticeChecked = false;
  bool _restoreRecoveryNoticeChecked = false;

  /// 已经提示过的连接失败序号。初值取挂载时的当前序号：挂载之前就已存在的失败
  /// 不重复弹窗。
  late int _shownFailureSeq;

  @override
  void initState() {
    super.initState();
    _shownFailureSeq = ref.read(connectionFailureProvider).seq;
  }

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
        showAiUiModal<void>(
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
          MaterialPageRoute<void>(
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
        QuickSettingsModal.show(context);
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_LOGS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const LogsPage()));
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_CONFIG_OPTIONS') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
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
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const AssetsPage()));
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_PER_APP_PROXY') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PerAppProxyPage()),
        );
      });
    }
    if (const bool.fromEnvironment('CLASHMIAO_OPEN_QR_SCANNER_DENIED') &&
        !_debugAddProfileOpened) {
      _debugAddProfileOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
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

    // 连接失败（spec §10 / 计划 P4 ③）：由连接状态机从内核快照与本地失败派生，
    // 按 failureSeq 去重。致命类（内核没起来 / 内核无响应）用阻断式弹窗——必须
    // 点确认，不能被用户划走错过；其余（未授权、超时、无订阅……用户仍可重试）
    // 维持非阻断 toast。文案统一走 connectionFailureMessage。
    ref.listen<ConnectionFailureView>(connectionFailureProvider, (_, next) {
      final failure = next.failure;
      if (failure == null || next.seq == _shownFailureSeq) return;
      _shownFailureSeq = next.seq;
      final t = ref.read(translationsProvider);
      final message = connectionFailureMessage(failure, t);
      if (failure.isFatal) {
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

    // alerts 通道只剩与连接生命周期无关的提示（例如通知权限请求）：照旧 toast。
    // 致命 alert 属于生命周期失败，已经由上面的连接失败监听统一弹窗，这里跳过，
    // 避免同一个故障提示两次。
    ref.listen<AsyncValue<BoxAlert>>(boxAlertsProvider, (_, next) {
      final alert = next.valueOrNull;
      if (alert == null || alert.type.isFatal) return;
      final t = ref.read(translationsProvider);
      AppToast.error(context, classifyBoxAlertMessage(alert, t));
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

    // 启动自愈清理掉了残留的系统代理时，告诉用户一声。
    //
    // 跟 deep-link 一样要"首帧补展示 + 后续 listen"两路：自愈发生在 main() 的
    // 启动流程里，比 ShellPage 挂载**早**，纯 ref.listen 会漏掉这一次唯一的
    // 变化。而不提示的话，用户的体感是"刚才网不通、重开 App 又好了"，下次再
    // 遇到还是一样懵——这件事必须从玄学变成一次可理解的故障。
    if (!_staleProxyNoticeChecked) {
      _staleProxyNoticeChecked = true;
      if (ref.read(staleProxyHealedNoticeProvider).isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showStaleProxyNotice(context, ref);
        });
      }
    }
    ref.listen<List<String>>(staleProxyHealedNoticeProvider, (prev, next) {
      if (next.isEmpty) return;
      _showStaleProxyNotice(context, ref);
    });

    // 上次备份恢复被中断、启动时自动回滚没成功（或快照没了）：首帧后明确告诉用户。
    // 启动屏障早于 ShellPage 挂载，结果只会在启动时写入一次，所以只需要首帧检查。
    if (!_restoreRecoveryNoticeChecked) {
      _restoreRecoveryNoticeChecked = true;
      if (needsStartupRestoreNotice(ref.read(startupRestoreRecoveryProvider))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showRestoreRecoveryNotice(context, ref);
        });
      }
    }

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
        body: Stack(
          children: [
            const Positioned.fill(child: BrandBackdrop()),
            Column(
              children: [
                if (topPad > 0) SizedBox(height: topPad),
                Expanded(
                  // 非当前 tab 虽然被 IndexedStack 藏起来了，但里面的 Ticker
                  // （循环动画、flutter_animate）照跑不误，白白耗帧。TickerMode
                  // 把它们静音；切回来时自动恢复。
                  child: IndexedStack(
                    index: selectedIndex,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        TickerMode(
                          key: ValueKey('tab_ticker_$i'),
                          enabled: i == selectedIndex,
                          child: _pages[i],
                        ),
                    ],
                  ),
                ),
              ],
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
/// 提示"上次异常退出残留的系统代理已清理"。
///
/// 用 info 而不是 success：从用户视角这不是一件他做成的事，而是一次**故障的
/// 事后说明**——上次退出不干净、机器的网络设置被留在了错误状态。用成功语气
/// 会让人以为是正常流程的一部分。
void _showStaleProxyNotice(BuildContext context, WidgetRef ref) {
  if (!context.mounted) return;
  AppToast.info(
    context,
    ref.read(translationsProvider).connection.staleSystemProxyCleaned,
  );
}

void _handleDeepLinkResult(
  BuildContext context,
  WidgetRef ref,
  DeepLinkImportResult result,
) {
  switch (result) {
    case DeepLinkImportSuccess(:final profileName):
      AppToast.success(
        context,
        ref
            .read(translationsProvider)
            .profile
            .add
            .importedNamed(name: profileName),
      );
    case DeepLinkImportFailure(:final message):
      // message 已是本地化文案（见 DeepLinkImportFailure）。
      AppToast.error(context, message);
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
    // 一律用 24 号那套字形：之前混用 20 号图标画在 22 px 上，字形的描边网格
    // 对不上像素，看起来又细又糊。图标本身也换成跟标签一致的意象——"主页"是
    // 房子而不是电源（电源是页面中央那颗连接按钮的语义，撞在一起会误读），
    // "线路"是地球而不是漏斗形的筛选图标。
    final items = [
      (
        FluentIcons.home_24_regular,
        FluentIcons.home_24_filled,
        t.home.pageTitle,
      ),
      (
        FluentIcons.globe_24_regular,
        FluentIcons.globe_24_filled,
        t.proxies.pageTitle,
      ),
      (
        FluentIcons.settings_24_regular,
        FluentIcons.settings_24_filled,
        t.settings.pageTitle,
      ),
      (
        FluentIcons.info_24_regular,
        FluentIcons.info_24_filled,
        t.about.pageTitle,
      ),
    ];
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    // 胶囊导航条：圆角取高度的一半，两侧留出边距浮在内容之上。阴影必须画在
    // ClipRRect **外面**——裁剪会把投影一起裁掉。
    // 高度对齐 Apple HIG 的标签栏：紧凑态 49pt / 常规 50pt。之前 58 比系统
    // 标签栏还高一截，图标周围全是空白。
    const barHeight = 50.0;
    final radius = BorderRadius.circular(barHeight / 2);

    return Padding(
      // 底边距不能直接加上整条安全区（iPhone 是 34pt）——那样胶囊会被顶到离
      // 屏幕底 46pt 的地方，整块导航占掉 100pt 以上。系统自己的浮动标签栏离
      // 底大约 20pt，正好在 Home Indicator 上方留出余量。
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        math.max(12, MediaQuery.of(context).padding.bottom - 14),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: aiUi.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: radius,
          // 不再套 BackdropFilter：底色是不透明实色，模糊压根看不见，却要
          // 每帧对导航条背后的整块内容做一次离屏模糊。
          child: Container(
            key: const ValueKey('bottom_nav_bar'),
            height: barHeight,
            decoration: BoxDecoration(
              // 用接近卡片的实色底把页面内容压住，避免亮色背景从导航后面
              // 透出来吃掉图标；边缘高光仍保留一点轻盈感。
              color: isLight
                  ? const Color(0xFFEEF1F7)
                  : const Color(0xFF1B1D24),
              borderRadius: radius,
              // 玻璃边：亮面用高光白描边，暗面用极淡的白，让边缘从背景里"起片"。
              border: Border.all(
                color: isLight
                    ? Colors.white.withValues(alpha: 0.6)
                    : const Color(0x1FFFFFFF),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: items.asMap().entries.map((entry) {
                final i = entry.key;
                final (icon, selectedIcon, label) = entry.value;
                final isSelected = i == selectedIndex;

                final color = isSelected
                    ? theme.colorScheme.primary
                    // 未选中在半透明玻璃上要比原来实一点，否则底下的内容
                    // 一流过去就把图标"吃"掉了。
                    : (isLight
                          ? aiUi.secondaryTextColor.withValues(alpha: 0.75)
                          : Colors.white.withValues(alpha: 0.55));

                return Expanded(
                  child: GestureDetector(
                    key: ValueKey('bottom_nav_$i'),
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    // 文字去掉了，但标签不能跟着消失——读屏用户靠它区分四个
                    // tab，图标本身对读屏是空的。
                    child: Semantics(
                      label: label,
                      button: true,
                      selected: isSelected,
                      child: Center(
                        // 选中态只靠颜色（图标换成 filled + 品牌蓝），不再垫
                        // 一块色块——整条已经是个胶囊，里面再套一个小方块是
                        // 两层容器打架。
                        child: Icon(
                          isSelected ? selectedIcon : icon,
                          color: color,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
