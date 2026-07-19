import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/egress_ip/egress_ip_service.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:clashmiao/features/home/widget/quick_settings_modal.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final connectionState = ref.watch(connectionControllerProvider);
    final status = connectionState.valueOrNull ?? const BoxStopped();
    final activeProfile = ref.watch(activeProfileProvider);
    final packageInfo = ref.watch(_packageInfoProvider);

    // 连接错误反馈：错误出现 → 弹 toast。只覆盖 connect()/disconnect() 的
    // 异常路径（SocketException/超时等）——致命 alert（内核没起来）不走这里，
    // 由 ShellPage 的 boxAlertsProvider 监听器弹阻断式弹窗，两边不重复提示。
    ref.listen<String?>(connectionErrorProvider, (prev, next) {
      if (next != null && next.isNotEmpty && context.mounted) {
        AppToast.error(context, next);
      }
    });

    // 配置变更触发的自动重连之前是纯静默的，用户可能把它误当成网络抖动。
    // ConnectionController 每次因为网络设置变更而自动重连时都会推进这个
    // nonce（见 app_providers.dart 里的文档），这里弹一条轻量提示，不阻断
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

    // 出口 IP：只在真正进入 BoxStarted 时才有意义地自动查（见
    // EgressIpService 类文档）。挂在 HomePage 这一级、而不是下沉到
    // `_FooterStats` 内部 listen，是因为 HomePage 在 `ShellPage` 的
    // `IndexedStack` 里全程常驻，而 `_FooterStats` 只是它的子组件、会随布局
    // 重建（窄屏两行 / 宽屏一行走不同分支）——监听点放在常驻的 HomePage 上
    // 更可靠，不会因为子组件重挂载而错过连接状态切换。
    ref.listen<AsyncValue<BoxStatus>>(connectionControllerProvider, (
      prev,
      next,
    ) {
      final wasStarted = prev?.valueOrNull is BoxStarted;
      final isStarted = next.valueOrNull is BoxStarted;
      if (wasStarted == isStarted) return;
      if (isStarted) {
        // 刚连接成功：先清空上一次的展示（可能是断开态手动查到的真实 IP，
        // 或者上一段连接的出口 IP），避免残留误导用户；开关开启时才自动查。
        // （竞态防护见 _resetEgressIpDisplay/_checkEgressIp 的文档。）
        _resetEgressIpDisplay(ref);
        if (ref.read(egressIpServiceProvider).autoCheckEnabled) {
          unawaited(_checkEgressIp(ref));
        }
      } else {
        // 断开（或者重连中途）：清空，不残留旧值。
        _resetEgressIpDisplay(ref);
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          // 背景光晕
          Positioned(
            top: -100,
            left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.0 : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // 顶部 Header
                  // shell_page 已统一处理顶部偏移
                  DragToMoveArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ClashMiao',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            packageInfo.maybeWhen(
                              data: (info) => Text(
                                'v${info.version}'.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Monospace',
                                  color: aiUi.secondaryTextColor,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              orElse: () => const SizedBox(),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _HeaderButton(
                              icon: FluentIcons.options_24_regular,
                              onTap: () => showAiUiModal(
                                context: context,
                                builder: (_) => const QuickSettingsModal(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _HeaderButton(
                              icon: FluentIcons.add_24_regular,
                              filled: true,
                              onTap: () {
                                final t = ref.read(translationsProvider);
                                _showAddProfileSheet(context, ref, t);
                              },
                            ),
                          ],
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
                              final connectionButtonSize = isCompact
                                  ? 220.0
                                  : 280.0;
                              return Column(
                                children: [
                                  _ActiveProfileCard(profile: profile),
                                  const Spacer(flex: 2),
                                  SizedBox(
                                    width: connectionButtonSize,
                                    height: connectionButtonSize,
                                    child: FittedBox(
                                      fit: BoxFit.contain,
                                      child: ConnectionButton(
                                        status: status,
                                        onTap: () {
                                          ref
                                              .read(
                                                connectionControllerProvider
                                                    .notifier,
                                              )
                                              .toggle();
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _ConnectionInfo(status: status),
                                  const SizedBox(height: 24),
                                  _ModeSelector(aiUi: aiUi),
                                  const Spacer(flex: 6),
                                  _FooterStats(compact: isCompact),
                                  const SizedBox(height: 16),
                                ],
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (e, _) {
                              final t = ref.watch(translationsProvider);
                              return Center(
                                child: Text('${t.failure.unexpected}: $e'),
                              );
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
  final bool filled;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? theme.colorScheme.primary : aiUi.softBackgroundColor,
          shape: BoxShape.circle,
          border: filled
              ? null
              : Border.all(color: aiUi.borderColor.withValues(alpha: 0.5)),
          boxShadow: filled ? aiUi.primaryShadow : null,
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled
              ? Colors.white
              : (isLight ? aiUi.secondaryTextColor : Colors.white70),
        ),
      ),
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
    } catch (_) {
      if (mounted) AppToast.error(context, t.profile.update.failureMsg);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;
    final t = ref.watch(translationsProvider);

    final profile = widget.profile;
    final canUpdate = _isRemoteProfile(profile);
    final subInfo = profile.subInfo;
    final total = subInfo?.total ?? 0;
    final percent = total > 0 ? subInfo!.usageRatio.clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onTap: () {
        showAiUiModal(
          context: context,
          builder: (context) => const _ProfilesOverviewSheet(),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : aiUi.glassColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: aiUi.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    FluentIcons.shield_24_filled,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Emoji',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10b981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 10,
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
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      tooltip: t.profile.update.tooltip,
                      icon: _isUpdating
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

/// 出口 IP 展示状态（首页级别，不下沉到 app_providers.dart——只有首页需要）。
///
/// `result == null` 表示"还没查过/已清空"（对应 UI 上的未知文案）；
/// `isLoading == true` 时展示加载态，此时 `result` 保留上一次的结果（查询期
/// 间不清空旧值，等新结果回来再整体替换，减少闪烁）。
class _EgressIpDisplay {
  const _EgressIpDisplay({this.isLoading = false, this.result});

  final bool isLoading;
  final EgressIpResult? result;

  static const idle = _EgressIpDisplay();
}

final _egressIpDisplayProvider = StateProvider<_EgressIpDisplay>(
  (ref) => _EgressIpDisplay.idle,
);

/// 出口 IP 展示状态的单调递增 generation。只用来防竞态——UI 不读也不 watch
/// 这个 provider。
///
/// 背景：一次查询（[EgressIpService.fetch]）要飞行 5~8 秒，这期间"当前该
/// 显示什么"完全可能已经变了——用户断开了连接、或者又发起了一次更新的查询。
/// `_EgressIpDisplay.isLoading` 只挡"同时发起第二个并发查询"，挡不住"一个
/// 更早发起、仍在飞行的旧查询在状态已经变了之后才 resolve，用旧值把新状态
/// 覆盖回去"这类竞态。两个真实会发生的场景：
/// 1. 断连竞态：连接成功→自动查询发起→用户在结果回来前断开→展示应该立刻
///    变回"未知"，但几秒后断连前发起的查询才 resolve，如果无条件写回，会把
///    tile 重新写成"连接时查到的隧道 IP"——用户已断开，却显示一个看起来仍
///    受保护的过期 IP。
/// 2. 反向：断开态手动点一次（慢）→紧接着点连接→触发一个新查询，更快
///    resolve 显示隧道 IP→但几秒后第一个更旧的查询才 resolve，如果无条件
///    写回，会覆盖回断连前的真实 ISP IP——用户已连接，却显示未受保护的 IP。
///
/// 做法：每次"当前该显示什么"发生改变的事件——连接状态切换（见
/// [_resetEgressIpDisplay]）、发起新一次查询（见 [_checkEgressIp]）——都
/// 递增这个计数器；[_checkEgressIp] 在发起查询前记下当时的值，`await`
/// 结束后跟最新值比对：不相等就说明查询期间发生过重置或者有更新的查询顶替
/// 了它，这次结果已经过期，必须丢弃，不能写回展示状态。
final _egressIpGenerationProvider = StateProvider<int>((ref) => 0);

/// 把出口 IP 展示重置为 idle，并让当前 generation 过期。
///
/// [HomePage] 里 `ref.listen(connectionControllerProvider, ...)` 的连接状态
/// 切换两个分支（连上、断开）都要调用——不管是"连上后先清空再自动查"还是
/// "断开后清空不残留"，两种情况下都必须让此刻仍在飞行的旧查询（不管是上一段
/// 连接触发的自动查询，还是断开态手动点的查询）在 resolve 时发现自己的
/// generation 已经过期而丢弃结果，不能让它事后覆盖这次重置。
void _resetEgressIpDisplay(WidgetRef ref) {
  final generation = ref.read(_egressIpGenerationProvider.notifier);
  generation.state = generation.state + 1;
  ref.read(_egressIpDisplayProvider.notifier).state = _EgressIpDisplay.idle;
}

/// 触发一次真实的出口 IP 查询并写回 [_egressIpDisplayProvider]。
///
/// 不检查 `clashmiao_auto_ip_check` 开关——是否要在调用这个函数之前先检查
/// 开关，由调用方决定：[HomePage] 的自动触发路径会先检查
/// `EgressIpService.autoCheckEnabled`；[_EgressIpTile] 的手动点击路径故意
/// 不检查，用户主动点击 = 明确意图，不受"自动检查"开关限制（合理的产品
/// 逻辑：开关只管"要不要自动帮你查"，不代表"允许不允许查"）。
///
/// 竞态防护：发起查询前先递增并记下 generation（[_egressIpGenerationProvider]
/// 的文档有完整背景），`fetch()` resolve 之后跟当时最新的 generation
/// 比对——如果这期间发生过连接状态切换（[_resetEgressIpDisplay]）或者又
/// 发起了一次更新的查询，generation 会被推进，这次结果就已经过期，直接
/// 丢弃，不写回展示状态。
Future<void> _checkEgressIp(WidgetRef ref) async {
  if (ref.read(_egressIpDisplayProvider).isLoading) return; // 避免重复并发查询
  final previous = ref.read(_egressIpDisplayProvider).result;
  final generation = ref.read(_egressIpGenerationProvider.notifier);
  final myGeneration = generation.state + 1;
  generation.state = myGeneration;
  ref.read(_egressIpDisplayProvider.notifier).state = _EgressIpDisplay(
    isLoading: true,
    result: previous,
  );
  final result = await ref.read(egressIpServiceProvider).fetch();
  if (ref.read(_egressIpGenerationProvider) != myGeneration) {
    return; // 期间已经过期（状态切换或者被更新的查询顶替），丢弃这次结果
  }
  ref.read(_egressIpDisplayProvider.notifier).state = _EgressIpDisplay(
    result: result,
  );
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
    final egressIp = ref.watch(_egressIpDisplayProvider);

    final trafficTile = _StatTile(
      icon: FluentIcons.data_usage_24_regular,
      label: t.stats.trafficUsage,
      value: formatBytes(total),
    );
    final speedTile = _StatTile(
      icon: FluentIcons.top_speed_24_filled,
      label: t.stats.liveSpeed,
      value: formatSpeed(stats?.downlink ?? 0),
    );
    final ipTile = _EgressIpTile(
      label: t.proxies.checkIp,
      unknownLabel: t.proxies.unknownIp,
      display: egressIp,
      onTap: () => unawaited(_checkEgressIp(ref)),
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

/// 出口 IP tile：展示当前查询结果（未知/加载中/IP+国旗），整块可点击触发
/// 手动重新检测。视觉语言（圆角、阴影、间距、配色）跟随 [_StatTile]，但
/// 独立成一个 widget——需要额外支持点击、加载态、国旗前缀，直接扩展
/// [_StatTile] 的话会让那个纯展示组件背上跟它无关的职责。
class _EgressIpTile extends StatelessWidget {
  const _EgressIpTile({
    required this.label,
    required this.unknownLabel,
    required this.display,
    required this.onTap,
  });

  final String label;
  final String unknownLabel;
  final _EgressIpDisplay display;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final result = display.result;
    final flag = _flagEmoji(result?.countryCode);

    final String valueText;
    if (result == null || result.isUnknown) {
      valueText = unknownLabel;
    } else if (flag != null) {
      valueText = '$flag ${result.ip}';
    } else {
      valueText = result.ip!;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: aiUi.softBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                FluentIcons.globe_search_24_regular,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 16),
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
                  Text(
                    valueText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (display.isLoading)
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
        ),
      ),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
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
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
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

class _ConnectionInfo extends ConsumerWidget {
  final BoxStatus status;
  const _ConnectionInfo({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isSwitching = status is BoxStarting || status is BoxStopping;
    final isConnected = status is BoxStarted;
    final isDisconnected = status is BoxStopped;

    // 我们尝试获取离线组或者在线组来展示节点名，临时用 fallback
    final groups = ref.watch(outboundGroupsProvider).valueOrNull ?? [];
    final t = ref.watch(translationsProvider);
    String nodeName = t.general.unknown;
    int delay = 0;
    if (groups.isNotEmpty && groups.first.items.isNotEmpty) {
      final selected = groups.first.selected;
      final activeItem = groups.first.items
          .where((i) => i.tag == selected)
          .firstOrNull;
      if (activeItem != null) {
        nodeName = activeItem.tag;
        delay = activeItem.delay;
      }
    }

    return AnimatedSize(
      duration: 300.ms,
      curve: Curves.easeOutBack,
      child: AnimatedSwitcher(
        duration: 300.ms,
        child: Builder(
          key: ValueKey(status.runtimeType),
          builder: (context) {
            if (isDisconnected) {
              return const SizedBox(height: 20);
            }
            if (isSwitching) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status is BoxStarting
                        ? 'Connecting...'
                        : 'Disconnecting...',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              );
            }
            if (isConnected) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.server_24_filled,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
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
                  Container(
                    width: 1,
                    height: 12,
                    color: theme.aiUi.borderColor,
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    FluentIcons.wifi_1_24_filled,
                    size: 16,
                    color: delay > 0
                        ? const Color(0xFF10B981)
                        : theme.aiUi.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    delay > 0 ? "${delay}ms" : "Checking",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: delay > 0
                          ? const Color(0xFF10B981)
                          : theme.aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              );
            }
            return const SizedBox(height: 20);
          },
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
    ref.read(proxyModeProvider.notifier).updateMode(index);

    // 全局 = execute-config-as-is: true（不走规则分流）
    // 智能 = execute-config-as-is: false（走规则分流）
    final isGlobal = index == 0;
    try {
      final service = ref.read(boxServiceProvider);
      // 推 fork-side options（mode 状态对齐，但路由是 RuntimeConfigBuilder 决定的）
      final options = getDefaultConfigOptions(
        executeConfigAsIs: isGlobal,
        settings: ref.read(networkSettingsProvider),
      );
      await service.changeConfigOptions(jsonEncode(options));

      // 如果当前在连接中，需要 reconnect 让新的 runtime-config 生效
      // —— 仅推 changeConfigOptions 不会让 sing-box 重读路由规则。
      final connStatus = ref.read(connectionControllerProvider).valueOrNull;
      if (connStatus is BoxStarted) {
        await ref.read(connectionControllerProvider.notifier).reconnect();
      }
    } catch (e) {
      final t = ref.read(translationsProvider);
      debugPrint(t.home.failedToSwitchMode(error: e.toString()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(proxyModeProvider);
    final t = ref.watch(translationsProvider);
    // 0=Global, 1=Smart。下标对齐 proxyModeProvider int。
    final modes = [t.home.routingMode.global, t.home.routingMode.smart];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.all(4),
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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.surface
              : theme.colorScheme.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.black.withValues(alpha: 0.08)
                  : Colors.transparent,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedDefaultTextStyle(
          duration: 200.ms,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.aiUi.secondaryTextColor,
          ),
          child: Text(text),
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
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.15),
                        const Color(0xFF10B981).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Icon(
                  FluentIcons.animal_paw_print_20_filled,
                  size: 120,
                  color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  shadows: [
                    Shadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      blurRadius: 30,
                    ),
                  ],
                ),
              ],
            ),
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
              '点击下方按钮开始探索',
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
                    Text(
                      t.profile.add.shortBtnTxt,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
            const Text(
              '未选择配置文件',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                showAiUiModal(
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
  const ConnectionInfoForTest({super.key, required this.status});

  final BoxStatus status;

  @override
  Widget build(BuildContext context) {
    return _ConnectionInfo(status: status);
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
