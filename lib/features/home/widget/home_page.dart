import 'dart:convert';
import 'dart:ui';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/utils/formatters.dart';
import 'package:clashmiao/features/home/widget/connection_button.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:window_manager/window_manager.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final connectionState = ref.watch(connectionControllerProvider);
    final status = connectionState.valueOrNull ?? const BoxStopped();
    final activeProfile = ref.watch(activeProfileProvider);

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
                  color: theme.colorScheme.primary.withValues(alpha: 
                    theme.brightness == Brightness.dark ? 0.0 : 0.08,
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
                            Text(
                              'v0.1.0',
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'Monospace',
                                color: aiUi.secondaryTextColor,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            _HeaderButton(
                              icon: FluentIcons.options_24_regular,
                              onTap: () {},
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

                  // 内容区
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: activeProfile.when(
                            data: (profile) {
                              if (profile == null) {
                                return _EmptyProfileBody(
                                  onAdd: () {
                                    final t = ref.read(translationsProvider);
                                    _showAddProfileSheet(context, ref, t);
                                  },
                                );
                              }
                              return Column(
                                children: [
                                  // 当前订阅卡片
                                  _ActiveProfileCard(profile: profile),

                                  const Spacer(flex: 2),

                                  // 连接按钮
                                  ConnectionButton(
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

                                  const SizedBox(height: 24),

                                  // 连接信息
                                  _ConnectionInfo(status: status),

                                  const SizedBox(height: 24),

                                  // 代理模式
                                  _ModeSelector(aiUi: aiUi),

                                  const Spacer(flex: 6),

                                  // 底部统计
                                  if (MediaQuery.sizeOf(context).width < 840)
                                    _FooterStats(aiUi: aiUi),

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
                                  child: Text('${t.failure.unexpected}: $e'));
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
      BuildContext context, WidgetRef ref, TranslationsEn t) {
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

class _ActiveProfileCard extends StatelessWidget {
  final ProfileEntity profile;
  const _ActiveProfileCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    final subInfo = profile.subInfo;
    final total = subInfo?.total ?? 0;
    final percent = total > 0 ? subInfo!.usageRatio.clamp(0.0, 1.0) : 0.0;

    return Container(
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
                            color: theme.colorScheme.primary.withValues(alpha: 0.6),
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
                  formatExpireDate(subInfo.expire),
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
      final activeItem =
          groups.first.items.where((i) => i.tag == selected).firstOrNull;
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

class _ModeSelector extends HookConsumerWidget {
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
      // 传完整配置，只改 execute-config-as-is
      final options = getDefaultConfigOptions(executeConfigAsIs: isGlobal);
      await service.changeConfigOptions(jsonEncode(options));
    } catch (e) {
      final t = ref.read(translationsProvider);
      debugPrint(t.home.failedToSwitchMode(error: e.toString()));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(proxyModeProvider);
    final isLight = theme.brightness == Brightness.light;
    final modes = ['全局', '智能'];

    return Container(
      width: 180,
      height: 44,
      decoration: BoxDecoration(
        color: aiUi.softBackgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: aiUi.borderColor,
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          // 滑块动画背景
          AnimatedAlign(
            duration: 300.ms,
            curve: Curves.fastOutSlowIn,
            alignment: mode == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isLight
                      ? Colors.white
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isLight ? 0.08 : 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Row(
            children: modes.asMap().entries.map((entry) {
              final i = entry.key;
              final label = entry.value;
              final isSelected = mode == i;

              return Expanded(
                child: _ModeItem(
                  label: label,
                  isActive: isSelected,
                  onTap: () => _onModeTap(i, ref),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends HookWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeItem({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaleCtrl = useAnimationController(
      duration: 120.ms,
      lowerBound: 0.95,
      upperBound: 1.0,
      initialValue: 1.0,
    );

    return GestureDetector(
      onTapDown: (_) => scaleCtrl.reverse(),
      onTapUp: (_) {
        scaleCtrl.forward();
        onTap();
      },
      onTapCancel: () => scaleCtrl.forward(),
      child: ScaleTransition(
        scale: scaleCtrl,
        child: AnimatedContainer(
          duration: 200.ms,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? Colors.transparent // Color is handled by the slider
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: AnimatedDefaultTextStyle(
            duration: 200.ms,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.aiUi.secondaryTextColor,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _FooterStats extends ConsumerWidget {
  const _FooterStats({required this.aiUi});
  final AiUiTheme aiUi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(boxStatsProvider).valueOrNull;
    final totalTraffic =
        (stats?.downlinkTotal ?? 0) + (stats?.uplinkTotal ?? 0);
    final t = ref.watch(translationsProvider);

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: FluentIcons.data_usage_24_regular,
            label: t.stats.trafficUsage,
            value: formatBytes(totalTraffic),
            aiUi: aiUi,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _StatTile(
            icon: FluentIcons.top_speed_24_filled,
            label: t.stats.liveSpeed,
            value: '${formatBytes(stats?.downlink ?? 0)}/s',
            aiUi: aiUi,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final AiUiTheme aiUi;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.aiUi,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

class _EmptyProfileBody extends ConsumerWidget {
  final VoidCallback onAdd;
  const _EmptyProfileBody({required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final t = ref.watch(translationsProvider);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 3),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: aiUi.softBackgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            FluentIcons.add_24_regular,
            size: 36,
            color: aiUi.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          t.home.emptyProfilesMsg,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: aiUi.secondaryTextColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '',
          style: TextStyle(
            fontSize: 13,
            color: aiUi.secondaryTextColor.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(FluentIcons.add_16_regular),
          label: Text(t.profile.add.shortBtnTxt),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        const Spacer(flex: 5),
      ],
    );
  }
}
