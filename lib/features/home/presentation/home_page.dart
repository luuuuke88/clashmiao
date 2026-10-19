import 'dart:async';
import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/routing/application/proxy_mode_notifier.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/application/profile_failures.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/domain/routing/model/node_display.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:clashmiao/core/theme/motion.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:clashmiao/domain/profile/application/expire_formatters.dart';
import 'package:clashmiao/domain/connection/application/connection_health_monitor.dart';
import 'package:clashmiao/features/home/presentation/connection_button.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/features/home/presentation/sleeping_brand_hero.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:clashmiao/shared/components/page_header.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:clashmiao/shared/components/motion_progress.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final phase = ref.watch(connectionPhaseProvider);
    final activeProfile = ref.watch(activeProfileProvider);
    final t = ref.watch(translationsProvider);

    // 配置变更触发的自动重连之前是纯静默的，用户可能把它误当成网络抖动。
    // ConnectionController 每次因为网络设置变更而自动重连时都会推进这个
    // nonce（见 connection_controller.dart 里的文档），这里弹一条轻量提示，不阻断
    // 操作。
    ref.listen<int>(configChangeReconnectNoticeProvider, (prev, next) {
      if (prev == next) return;
      if (context.mounted) {
        AppToast.info(
          context,
          ref.read(translationsProvider).connection.reconnectMsg,
        );
      }
    });

    // 背景晕染统一由 ShellPage 底下那层 BrandBackdrop 画，页面自己保持透明。
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              // 上边距 24 dp，与线路页页头同高同位。
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                children: [
                  // 顶部页头：与线路页同一个 PageHeader（标题 24 sp、最小高 48 dp、
                  // 按钮与标题垂直居中），不再带版本号——版本在「关于」页。
                  // shell_page 已统一处理顶部偏移
                  DragToMoveArea(
                    child: PageHeader(
                      title: 'ClashMiao',
                      actions: [
                        _HeaderButton(
                          icon: FluentIcons.options_24_regular,
                          tooltip: t.config.quickSettings,
                          onTap: () => QuickSettingsModal.show(context),
                        ),
                        _HeaderButton(
                          icon: FluentIcons.add_24_regular,
                          tooltip: t.profile.add.buttonText,
                          filled: true,
                          onTap: () => _showAddProfileSheet(context, ref, t),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: activeProfile.when(
                            data: (profile) {
                              // 核心库都没加载起来的时候，订阅有没有、连不连得上
                              // 都是次要的——整个 App 就是个空壳。这一层守卫要在
                              // 所有其它状态之前，否则用户看到的是一个完全正常的
                              // 界面加一个点了没反应的连接按钮。
                              if (ref.watch(coreLibraryMissingProvider)) {
                                return const _CoreMissingBody();
                              }
                              if (profile == null) {
                                return _EmptyHomeBody(
                                  onAdd: () {
                                    final t = ref.read(translationsProvider);
                                    _showAddProfileSheet(context, ref, t);
                                  },
                                );
                              }
                              final isCompact =
                                  MediaQuery.sizeOf(context).width < 840;
                              // 猫与圆盘的缩放（设计尺寸 300 → 窄屏 220 / 宽屏 280），
                              // 状态文字不随之缩小。
                              final connectionButtonScale = isCompact
                                  ? 220.0 / 300
                                  : 280.0 / 300;
                              return Column(
                                children: [
                                  _ActiveProfileCard(profile: profile),
                                  const Spacer(flex: 2),
                                  ConnectionButton(
                                    phase: phase,
                                    scale: connectionButtonScale,
                                    onTap: () {
                                      unawaited(
                                        ref
                                            .read(
                                              connectionControllerProvider
                                                  .notifier,
                                            )
                                            .toggle(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 24),
                                  _ConnectionInfo(phase: phase),
                                  const _DegradedConnectionNotice(),
                                  const SizedBox(height: 20),
                                  _ModeSelector(aiUi: aiUi),
                                  const SizedBox(height: 16),
                                  _FooterStats(compact: isCompact),
                                  // 富余高度全部留到最下面：数据块紧跟在模式
                                  // 切换下面是一组，中间撑开一大段的话它们看
                                  // 起来跟上面就没关系了。底部也正好让开浮起
                                  // 来的胶囊导航。
                                  const Spacer(flex: 5),
                                ],
                              );
                            },
                            // 整页加载：减少动画时停成静态弧，语义仍是「加载中」。
                            loading: () => const Center(
                              child: MotionProgress(strokeWidth: 4),
                            ),
                            error: (e, _) {
                              debugPrint('首页读取订阅失败: $e');
                              final t = ref.watch(translationsProvider);
                              return Center(child: Text(t.failure.unexpected));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddProfileSheet(
    BuildContext context,
    WidgetRef ref,
    TranslationsEn t,
  ) {
    showProfileFormDialog(context, ref);
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool filled;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: icon,
      tooltip: tooltip,
      filled: filled,
      onTap: onTap,
    );
  }
}

class _ActiveProfileCard extends ConsumerStatefulWidget {
  final ProfileEntity profile;
  const _ActiveProfileCard({required this.profile});

  @override
  ConsumerState<_ActiveProfileCard> createState() => _ActiveProfileCardState();
}

class _ActiveProfileCardState extends ConsumerState<_ActiveProfileCard> {
  bool _isUpdating = false;

  bool _isRemoteProfile(ProfileEntity profile) {
    final uri = Uri.tryParse(profile.url.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _updateProfile(ProfileEntity profile, TranslationsEn t) async {
    if (_isUpdating || !_isRemoteProfile(profile)) return;
    setState(() => _isUpdating = true);
    try {
      final repo = await ref.read(profileRepositoryProvider.future);
      await repo.update(profile.id);
      ref.invalidate(profileListProvider);
      ref.invalidate(activeProfileProvider);
      if (mounted) AppToast.success(context, t.profile.update.successMsg);
    } catch (e) {
      if (isStaleRefresh(e)) {
        // 刷新途中订阅被改动，结果已作废：这是预期内的取消，不提示失败。
        // 不再手动 invalidate：造成作废的那次提交已经通过 ProfileStore.changes
        // 让两个 provider 重新计算；而页面此时可能已销毁，销毁后碰 ref 会抛异常。
      } else if (mounted) {
        AppToast.error(
          context,
          profileStoreErrorMessage(e, () => t) ?? t.profile.update.failureMsg,
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final t = ref.watch(translationsProvider);

    final profile = widget.profile;
    final canUpdate = _isRemoteProfile(profile);
    final subInfo = profile.subInfo;
    final total = subInfo?.total ?? 0;
    final percent = total > 0 ? subInfo!.usageRatio.clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        showAiUiModal<void>(
          context: context,
          builder: (context) => const _ProfilesOverviewSheet(),
        );
      },
      child: GlassCard(
        borderRadius: 14,
        // 这张卡只有一行内容，上下留 10 就够——留 14 会让它比中间那颗按钮
        // 还抢戏。
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    FluentIcons.shield_24_filled,
                    color: theme.colorScheme.primary,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.2,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Emoji',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: StatusColors.connected(theme.brightness),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.2,
                              fontWeight: FontWeight.bold,
                              color: aiUi.secondaryTextColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (canUpdate)
                  // 视觉图标 18 dp，交互区 48×48（Android 最小触控目标）。
                  SizedBox(
                    width: kMinInteractiveDimension,
                    height: kMinInteractiveDimension,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: t.profile.update.tooltip,
                      // 更新中旋转；系统开了「减少动画」时停在静态图标上。
                      icon: _isUpdating && Motion.loops(context)
                          ? Icon(
                                  FluentIcons.arrow_sync_24_regular,
                                  size: 18,
                                  color: aiUi.secondaryTextColor,
                                )
                                .animate(
                                  onPlay: (controller) => controller.repeat(),
                                )
                                .rotate(duration: 1.seconds)
                          : Icon(
                              FluentIcons.arrow_sync_24_regular,
                              size: 18,
                              color: aiUi.secondaryTextColor,
                            ),
                      onPressed: _isUpdating
                          ? null
                          : () => _updateProfile(profile, t),
                    ),
                  ),
              ],
            ),
            if (subInfo != null) ...[
              const SizedBox(height: 16),
              if (total > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: aiUi.softBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: percent,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              const Color(0xFF22d3ee),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.6,
                              ),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // 用量与到期日：放得下就两端对齐，放不下（窄屏 / 大字号）自动折到
              // 下一行，不把行撑出卡片。
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '${SubscriptionInfo.formatBytes(subInfo.used)} / ${SubscriptionInfo.formatBytes(subInfo.total)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: aiUi.secondaryTextColor,
                    ),
                  ),
                  Text(
                    formatExpireDate(subInfo.expire, t),
                    style: TextStyle(
                      fontSize: 12,
                      color: aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ] else
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProfilesOverviewSheet extends StatelessWidget {
  const _ProfilesOverviewSheet();

  @override
  Widget build(BuildContext context) {
    return const ProfilesPage(embedInSheet: true);
  }
}

/// ISO 3166-1 alpha-2 两位国家码转区域指示符 emoji（比如 'JP' -> 🇯🇵）。
/// 不是恰好两位 A-Z 字母就返回 null——只是不展示国旗，不影响 IP 文本本身。
String? _flagEmoji(String? countryCode) {
  if (countryCode == null || countryCode.length != 2) return null;
  const asciiA = 0x41; // 'A'
  const regionalIndicatorBase = 0x1F1E6; // Regional Indicator Symbol Letter A
  final upper = countryCode.toUpperCase();
  final units = <int>[];
  for (final unit in upper.codeUnits) {
    if (unit < asciiA || unit > asciiA + 25) return null;
    units.add(regionalIndicatorBase + (unit - asciiA));
  }
  return String.fromCharCodes(units);
}

class _FooterStats extends ConsumerWidget {
  const _FooterStats({required this.compact});

  /// 窄屏（竖屏手机）走两行布局；宽屏（横屏手机 / 平板）走三 tile 一行。
  /// 由 [HomePage] 用它已经算好的 `isCompact` 传入，让断点判断保持单一来源
  /// （同一个 `< 840` 也决定连接按钮大小），避免这里再读一次 MediaQuery 各
  /// 算各的、两边漂移。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final stats = ref.watch(boxStatsProvider).valueOrNull;
    final total = (stats?.downlinkTotal ?? 0) + (stats?.uplinkTotal ?? 0);
    final egressIp = ref.watch(egressIpProbeProvider);

    final trafficTile = _StatTile(
      icon: FluentIcons.data_usage_24_regular,
      label: t.stats.sessionTraffic,
      value: formatBytes(total),
    );
    final speedTile = _StatTile(
      icon: FluentIcons.top_speed_24_filled,
      label: t.stats.downloadSpeed,
      value: formatSpeed(stats?.downlink ?? 0),
    );
    final ipTile = _EgressIpTile(
      label: t.home.egressIp.label,
      texts: (
        notConnected: t.home.egressIp.notConnected,
        tapToCheck: t.home.egressIp.tapToCheck,
        checking: t.home.egressIp.checking,
        failedRetry: t.home.egressIp.failedRetry,
      ),
      display: egressIp,
      onTap: () =>
          unawaited(ref.read(egressIpProbeProvider.notifier).checkNow()),
    );

    // 宽屏（≥840，实际只有横屏手机 / 平板会触发——桌面窗口锁死 420 宽、永远
    // 窄屏）：三个 tile 排成一行，用满宽屏横向空间、只占一行高度（横屏手机
    // 纵向很紧）。maxWidth 收口 + 居中，避免在大平板上被拉得过宽显得空。
    //
    // flex 3:3:4——检测 IP tile 分到更宽的一份：它固定占用的图标 / 内边距 /
    // 尾部刷新图标就吃掉约 112px，等分三份的话留给 IP 文本只剩约 110px，一个
    // 带国旗的完整 IPv4（如「🇯🇵 156.243.244.222」约 136px）会被 ellipsis 截断，
    // 检测 IP 就失去意义了；给它 4/10 后文本区约 155px，留有余量。流量 / 速度
    // 的值很短（如「1.23 GB」），3/10 绰绰有余。
    if (!compact) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Row(
            children: [
              Expanded(flex: 3, child: trafficTile),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: speedTile),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: ipTile),
            ],
          ),
        ),
      );
    }

    // 窄屏（竖屏手机，保持原样）：流量 + 速度并排一行，检测 IP tile 整行在下。
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: trafficTile),
            const SizedBox(width: 16),
            Expanded(child: speedTile),
          ],
        ),
        const SizedBox(height: 16),
        ipTile,
      ],
    );
  }
}

/// 出口 IP 卡的四条文案（连同成功时的 IP 本身，共五种内容）。
typedef _EgressTexts = ({
  String notConnected,
  String tapToCheck,
  String checking,
  String failedRetry,
});

/// 出口 IP 卡（UI 设计 §1）。内容由 [EgressIpState] 唯一决定：
/// - 未连接 → 「连接后显示出口 IP」，整卡不可点、没有刷新图标；
/// - 已连接但未检测（自动检测关闭）→ 「点击检测出口 IP」；
/// - 查询中 → 「正在检测…」+ 转圈，不显示「未知的 IP」；
/// - 全部失败 → 「检测失败，点击重试」；
/// - 成功 → 完整 IP（带国旗；IPv6 允许换行，不省略）。
///
/// 视觉语言（圆角、阴影、间距、配色）跟随 [_StatTile]，但独立成一个 widget——
/// 需要额外支持点击、加载态、国旗前缀，直接扩展 [_StatTile] 会让那个纯展示
/// 组件背上跟它无关的职责。
class _EgressIpTile extends StatelessWidget {
  const _EgressIpTile({
    required this.label,
    required this.texts,
    required this.display,
    required this.onTap,
  });

  final String label;
  final _EgressTexts texts;
  final EgressIpState display;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final status = display.status;
    final result = display.result;
    final flag = _flagEmoji(result?.countryCode);

    final isSuccess =
        status == EgressIpStatus.success && result != null && !result.isUnknown;
    final String valueText;
    if (isSuccess) {
      valueText = flag != null ? '$flag ${result.ip}' : result.ip!;
    } else {
      valueText = switch (status) {
        EgressIpStatus.notConnected => texts.notConnected,
        EgressIpStatus.idle => texts.tapToCheck,
        EgressIpStatus.checking => texts.checking,
        EgressIpStatus.failed => texts.failedRetry,
        // 成功态却没有 IP（不该发生）按「可再点一次」呈现。
        EgressIpStatus.success => texts.tapToCheck,
      };
    }
    final tappable = status != EgressIpStatus.notConnected;
    final muted = status == EgressIpStatus.notConnected;

    final card = SizedBox(
      width: double.infinity,
      child: GlassCard(
        borderRadius: 14,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                FluentIcons.globe_search_24_regular,
                size: 17,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: aiUi.secondaryTextColor,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 不设 maxLines / ellipsis：完整 IPv6 必须能换行看全。
                  Text(
                    valueText,
                    key: const ValueKey('egress-ip-value'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSuccess ? FontWeight.w700 : FontWeight.w600,
                      color: muted
                          ? aiUi.secondaryTextColor
                          : theme.colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 12),
              if (status == EgressIpStatus.checking)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  FluentIcons.arrow_sync_24_regular,
                  size: 16,
                  color: aiUi.secondaryTextColor,
                ),
            ],
          ],
        ),
      ),
    );

    if (!tappable) return card;
    return Semantics(
      button: true,
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;

    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: aiUi.secondaryTextColor,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                // 等宽数字：数值直接更新（不滚动），位数变化时不抖动。
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 节点区：已连接时显示当前生效节点的胶囊，其余阶段留白。
///
/// 高度固定 48 dp（连接状态切换时页面不跳动）；出现 / 消失只做 180 ms 淡入淡出
/// （UI 设计 §2：不再有 easeOutBack 的弹性高度）。过渡期的加载指示在连接按钮
/// 上（延迟出现的加载环），这里不重复。
class _ConnectionInfo extends ConsumerWidget {
  final ConnectionPhase phase;
  const _ConnectionInfo({required this.phase});

  /// 节点区固定高度。
  static const double height = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isConnected = phase == ConnectionPhase.connected;

    // 当前生效节点。两层修复（真机 VLESS+Reality 订阅实测：连接成功、线路页
    // 正常，唯独首页显示"未知"）：
    //   1. 数据源：核心 command server 的实时分组（outboundGroupsProvider）
    //      有时是空的（还没订阅上 / 没推），首页此前只读它就只能显示"未知"。
    //      线路页早有 offline 兜底——空时回退到从 profile 配置解析的分组
    //      （offlineProxyGroupsProvider）。首页现在对齐同一套兜底。
    //   2. 解析：不再直接取 `groups.first.selected`（第一条可能是 GLOBAL 或
    //      selected 指向嵌套分组的选择器，解不到叶子），改用 resolveActiveProxy
    //      跳过伪分组、优先主选择器 proxy、下钻到叶子节点。
    final liveGroups = ref.watch(outboundGroupsProvider).valueOrNull ?? [];
    final offlineGroups =
        ref.watch(offlineProxyGroupsProvider).valueOrNull ?? [];
    final isLiveData = liveGroups.any((g) => g.items.isNotEmpty);
    // 离线兜底叠加存储里的手选（与代理页同一口径）：重放的就是它。
    final groups = isLiveData
        ? liveGroups
        : applyStoredSelections(
            offlineGroups,
            ref.watch(proxySelectionStoreProvider),
          );
    final t = ref.watch(translationsProvider);
    final activeItem = resolveActiveProxy(groups);
    // 展示名与代理页同一套逻辑（node_display）：去掉 `§` 后缀，旗帜放在名称前。
    // 原始 tag 只用于选择与缓存。
    final String nodeName = activeItem == null
        ? t.general.unknown
        : NodeDisplay.parse(activeItem.tag).capsuleName ?? t.general.unknown;
    // 延迟展示与代理页同一套：同一个缓存、同一个协调器状态、同一个解析函数，
    // 两处不会出现一个有数字一个是破折号的分歧。
    final latencyState = ref.watch(latencyTestCoordinatorProvider);
    final cachedDelay = activeItem == null
        ? null
        : ref.watch(proxyDelayCacheProvider)[activeItem.tag];
    final latency = resolveNodeLatency(
      liveMs: activeItem?.delay ?? 0,
      cachedMs: cachedDelay?.ms,
      cachedAt: cachedDelay?.measuredAt,
      testing:
          activeItem != null &&
          latencyState.isNodePendingInAnyGroup(activeItem.tag),
      timedOut:
          activeItem != null &&
          latencyState.timedOutNodes.contains(activeItem.tag),
      unconfirmed:
          activeItem != null &&
          latencyState.unconfirmedNodes.contains(activeItem.tag),
      now: ref.watch(latencyClockProvider)(),
      cacheIsFallback: !isLiveData,
    );

    Widget pill() {
      // 做成带箭头的胶囊而不是一行字：原来那样看不出能点，左边的服务器图标在
      // 小尺寸下还像一部手机。点了直接跳线路页换节点。
      return Semantics(
        button: true,
        child: GestureDetector(
          onTap: () =>
              ref.read(selectedTabProvider.notifier).state = AppTab.proxies,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(
              color: theme.aiUi.softBackgroundColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.aiUi.borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    nodeName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                // 延迟只是一行文字：不再配 Wi-Fi 图标，状态靠数字与颜色表达。
                LatencyLabel(
                  state: latency.state,
                  ms: latency.ms,
                  fontSize: 14,
                ),
                const SizedBox(width: 6),
                Icon(
                  FluentIcons.chevron_right_16_regular,
                  size: 16,
                  color: theme.aiUi.secondaryTextColor,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: KeyedSubtree(
          // 只按「是否已连接」换 key：connecting ↔ disconnecting 之类的过渡之间
          // 都是留白，不需要淡入淡出。
          key: ValueKey(isConnected),
          child: isConnected ? pill() : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

class _ModeSelector extends ConsumerWidget {
  const _ModeSelector({required this.aiUi});
  final AiUiTheme aiUi;

  Future<void> _onModeTap(int index, WidgetRef ref) async {
    final current = ref.read(proxyModeProvider);
    if (current == index) return;
    // 同步更新，保证点击零延迟高亮——实际让内核用上新模式的逻辑（含连续
    // 快速切换时的排队/收敛）在 ConnectionController.applyProxyMode 里，
    // 见其文档注释（曾经真机实锤过 UI/内核路由模式静默错位的 bug）。
    // await 而不是 fire-and-forget：state 是在 updateMode 内部**同步**赋值的，
    // 所以"点击零延迟高亮"不受影响；异步的只有 `prefs.setInt`。不 await 的话
    // 写失败会变成一条没人接的异步异常——UI 显示新模式、重启后静默回退到旧模式。
    await ref.read(proxyModeProvider.notifier).updateMode(index);
    await ref.read(connectionControllerProvider.notifier).applyConfig();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(proxyModeProvider);
    final t = ref.watch(translationsProvider);
    // 0=Global, 1=Smart。下标对齐 proxyModeProvider int。
    final modes = [t.home.routingMode.global, t.home.routingMode.smart];

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(19),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: modes.asMap().entries.map((entry) {
          final i = entry.key;
          final label = entry.value;
          return _SegmentTab(
            text: label,
            isSelected: mode == i,
            onTap: () => _onModeTap(i, ref),
          );
        }).toList(),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentTab({
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // 分段控件的每一段：按钮 + 选中语义（读屏念「已选择」），互斥组。
    return Semantics(
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.duration(context, Motion.short),
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          // 选中项用 primaryContainer / onPrimaryContainer 这一对（与快速设置
          // 里的分段控件同一套角色）。原来填的是 colorScheme.surface：深色
          // 主题下它比底槽还暗，选中跟没选中只差一点字重，真机上分不出来。
          decoration: BoxDecoration(
            color: isSelected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: AnimatedDefaultTextStyle(
            duration: Motion.duration(context, Motion.short),
            curve: Motion.standard,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? scheme.onPrimaryContainer
                  : theme.aiUi.secondaryTextColor,
            ),
            child: Text(text),
          ),
        ),
      ),
    );
  }
}

/// "已连接但实际不通"（黑洞）的告警条。
///
/// 这是这个 App 此前完全缺失的一层反馈：内核报 `BoxStarted` 之后 UI 就一直
/// 显示"已连接"，哪怕真实 egress 早已不通、整机流量被黑洞掉，用户看到的还是
/// "VPN 连着呢"。判定逻辑见 [ConnectionHealthMonitor]。
///
/// 这里只提示、不自动断开——误杀一条健康连接比让用户自己决定要糟糕得多，
/// 理由详见 [ConnectionHealthMonitor] 的类文档。
class _DegradedConnectionNotice extends ConsumerWidget {
  const _DegradedConnectionNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(connectionHealthProvider);
    if (health != ConnectionHealth.degraded) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              FluentIcons.warning_20_filled,
              size: 20,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.home.degradedTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.home.degradedMsg,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => unawaited(
                      ref.read(connectionHealthProvider.notifier).probeNow(),
                    ),
                    child: Text(t.home.degradedRetry),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面端 libcore 加载失败时的阻断态。
///
/// 修复前这个状态在界面上**完全不可见**：`BoxService` 工厂 catch 住加载异常、
/// 静默降级成桩实现，首页照常渲染连接按钮，用户点了没有任何反应也没有任何
/// 解释。这里换成一个说清楚"出了什么事、怎么办"的阻断页。
class _CoreMissingBody extends ConsumerWidget {
  const _CoreMissingBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.plug_disconnected_24_filled,
              size: 72,
              color: theme.colorScheme.error.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 20),
            Text(
              t.home.coreMissingTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t.home.coreMissingMsg,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeBody extends ConsumerWidget {
  const _EmptyHomeBody({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profileListProvider);
    return profiles.maybeWhen(
      data: (items) {
        if (items.isNotEmpty) {
          return const _EmptyActiveProfileBody();
        }
        return _EmptyProfileBody(onAdd: onAdd);
      },
      orElse: () => _EmptyProfileBody(onAdd: onAdd),
    );
  }
}

class _EmptyProfileBody extends ConsumerWidget {
  const _EmptyProfileBody({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final t = ref.watch(translationsProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SleepingBrandHero(),
            const SizedBox(height: 40),
            Text(
              t.home.emptyProfilesMsg,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.home.emptyProfilesHint,
              style: TextStyle(fontSize: 14, color: aiUi.secondaryTextColor),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: aiUi.softBackgroundColor,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: aiUi.borderColor.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.add_24_regular,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    // Flexible：窄屏 / 大字号 / 长翻译下文字换行，不把行撑出屏。
                    Flexible(
                      child: Text(
                        t.profile.add.shortBtnTxt,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActiveProfileBody extends ConsumerWidget {
  const _EmptyActiveProfileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final t = ref.watch(translationsProvider);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                FluentIcons.warning_24_regular,
                size: 48,
                color: Colors.orange.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t.home.noActiveProfileTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              t.home.noActiveProfileMsg,
              style: TextStyle(fontSize: 14, color: aiUi.secondaryTextColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: () {
                showAiUiModal<void>(
                  context: context,
                  builder: (context) => const _ProfilesOverviewSheet(),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  t.profile.overviewPageTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 测试用 export：暴露私有 `_ModeSelector` 给 widget test 使用。
///
/// 不要在生产代码中使用 —— 此 wrapper 仅为绕开私有可见性。
class ModeSelectorForTest extends StatelessWidget {
  const ModeSelectorForTest({super.key});

  @override
  Widget build(BuildContext context) {
    return _ModeSelector(aiUi: Theme.of(context).aiUi);
  }
}

/// 测试用 export：暴露私有 `_ConnectionInfo` 给 widget test 使用。
///
/// 不要在生产代码中使用 —— 此 wrapper 仅为绕开私有可见性。
class ConnectionInfoForTest extends StatelessWidget {
  const ConnectionInfoForTest({super.key, required this.phase});

  final ConnectionPhase phase;

  @override
  Widget build(BuildContext context) {
    return _ConnectionInfo(phase: phase);
  }
}

/// 测试用 export：暴露私有 `_FooterStats` 给 widget test 使用。
///
/// 不要在生产代码中使用 —— 此 wrapper 仅为绕开私有可见性。
class FooterStatsForTest extends StatelessWidget {
  const FooterStatsForTest({super.key, this.compact = true});

  /// 默认走窄屏两行布局，跟历史 widget test 的既有断言一致；宽屏一行布局的
  /// 测试显式传 `compact: false`。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _FooterStats(compact: compact);
  }
}
