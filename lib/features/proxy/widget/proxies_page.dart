import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/proxy/state/optimistic_proxy_selections_notifier.dart';
import 'package:clashmiao/features/proxy/state/proxies_sort_notifier.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesPage extends ConsumerWidget {
  const ProxiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final isConnected = ref.watch(isConnectedProvider);
    final sortBy = ref.watch(proxiesSortProvider);
    final optimisticSelections = ref.watch(optimisticProxySelectionsProvider);

    // 已连接时优先使用实时数据，否则用离线解析
    final liveGroups = ref.watch(outboundGroupsProvider);
    final offlineGroups = ref.watch(offlineProxyGroupsProvider);

    List<OutboundGroup> rawGroups;
    if (isConnected) {
      rawGroups = liveGroups.when<List<OutboundGroup>>(
        data: (g) => g.isNotEmpty ? g : (offlineGroups.valueOrNull ?? []),
        loading: () => offlineGroups.valueOrNull ?? [],
        error: (_, __) => offlineGroups.valueOrNull ?? [],
      );
    } else {
      rawGroups = offlineGroups.valueOrNull ?? [];
    }

    // 过滤掉内部保留字分组并进行排序
    final List<OutboundGroup> groups = [];
    for (final group in rawGroups) {
      if (group.tag.toUpperCase() == 'GLOBAL' ||
          group.tag.toUpperCase() == 'DIRECT' ||
          group.tag.toUpperCase() == 'REJECT') {
        continue;
      }

      final sortedItems = List<OutboundProxy>.from(group.items);
      if (sortBy == ProxiesSort.name) {
        sortedItems.sort((a, b) => a.tag.compareTo(b.tag));
      } else if (sortBy == ProxiesSort.delay) {
        sortedItems.sort((a, b) {
          final ai = a.delay;
          final bi = b.delay;
          if (ai <= 0 && bi <= 0) return 0;
          if (ai <= 0 && bi > 0) return 1;
          if (ai > 0 && bi <= 0) return -1;
          return ai.compareTo(bi);
        });
      }

      final currentSelected = optimisticSelections[group.tag] ?? group.selected;

      groups.add(
        OutboundGroup(
          tag: group.tag,
          type: group.type,
          selected: currentSelected,
          items: sortedItems,
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.proxies.pageTitle,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _HeaderButton(
                        icon: FluentIcons.arrow_sort_24_regular,
                        onTap: () {
                          showAiUiModal(
                            context: context,
                            builder: (context) => const ProxiesSortModal(),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      _HeaderButton(
                        icon: FluentIcons.flash_24_regular,
                        onTap: isConnected
                            ? () => _testAll(context, ref, groups)
                            : () {
                                AppToast.info(context,
                                    t.failure.singbox.serviceNotRunning);
                              },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Content
              Expanded(
                child: groups.isEmpty
                    ? const _EmptyProxy()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120),
                        itemCount: groups.length,
                        itemBuilder: (ctx, index) {
                          final group = groups[index];
                          // Identify Auto/URL-Test item
                          final autoProxy = group.items.firstWhereOrNull(
                                (e) =>
                                    e.type.toLowerCase() == 'urltest' ||
                                    e.type.toLowerCase() == 'url_test',
                              ) ??
                              group.items.firstWhereOrNull(
                                (e) => e.tag.toLowerCase() == 'auto',
                              );
                          final otherProxies =
                              group.items.where((e) => e != autoProxy).toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _GroupHeader(
                                group: group,
                                isConnected: isConnected,
                                onTest: isConnected
                                    ? () {
                                        ref
                                            .read(boxServiceProvider)
                                            .urlTest(group.tag);
                                        AppToast.info(
                                          context,
                                          t.proxies.testingDelayInfo(
                                              name: group.tag),
                                        );
                                      }
                                    : null,
                              ),
                              if (autoProxy != null)
                                _AutoSelectCard(
                                  isSelected: group.selected == autoProxy.tag,
                                  onTap: () => _selectProxy(
                                    context,
                                    ref,
                                    group.tag,
                                    autoProxy.tag,
                                    isConnected,
                                  ),
                                ),
                              ...otherProxies.map((proxy) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ProxyTile(
                                    proxy: proxy,
                                    isSelected: group.selected == proxy.tag,
                                    onTap: () => _selectProxy(
                                      context,
                                      ref,
                                      group.tag,
                                      proxy.tag,
                                      isConnected,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectProxy(
    BuildContext context,
    WidgetRef ref,
    String groupTag,
    String outboundTag,
    bool isConnected,
  ) {
    final t = ref.read(translationsProvider);
    if (isConnected) {
      ref
          .read(optimisticProxySelectionsProvider.notifier)
          .update(groupTag, outboundTag);
      ref
          .read(boxServiceProvider)
          .selectOutbound(groupTag, outboundTag)
          .then((_) {
        // Toast can be annoying on fast switches, removed or keep brief
        // AppToast.success(context, t.proxies.switchedTo(name: outboundTag));
      }).catchError((e) {
        if (!context.mounted) return;
        AppToast.error(context, t.proxies.switchToFailed(error: e.toString()));
      });
    } else {
      AppToast.info(context, t.proxies.connectBeforeSwitch);
    }
  }

  void _testAll(
    BuildContext context,
    WidgetRef ref,
    List<OutboundGroup> groups,
  ) {
    for (final g in groups) {
      ref.read(boxServiceProvider).urlTest(g.tag);
    }
    final t = ref.read(translationsProvider);
    AppToast.info(context,
        t.proxies.startDelayTestForGroups(count: groups.length.toString()));
  }
}

class ProxiesSortModal extends HookConsumerWidget {
  const ProxiesSortModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final sortBy = ref.watch(proxiesSortProvider);

    return AiUiModalWrapper(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Text(
                  t.proxies.sortModalTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          ...ProxiesSort.values.map((e) {
            final icon = switch (e) {
              ProxiesSort.unsorted => FluentIcons.list_24_regular,
              ProxiesSort.name => FluentIcons.text_sort_ascending_24_regular,
              ProxiesSort.delay => FluentIcons.cellular_data_1_24_regular,
            };

            return ListTile(
              title: Text(e.present(t)),
              leading: Icon(icon),
              selected: sortBy == e,
              trailing: sortBy == e
                  ? Icon(
                      FluentIcons.checkmark_24_filled,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                ref.read(proxiesSortProvider.notifier).updateSort(e);
                context.pop();
              },
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: (200 + e.index * 50).ms)
                .slideX(
                  begin: 0.1,
                  end: 0,
                  duration: 300.ms,
                  delay: (200 + e.index * 50).ms,
                );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).aiUi.softBackgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).aiUi.borderColor),
        ),
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      ),
    );
  }
}

class _AutoSelectCard extends HookConsumerWidget {
  const _AutoSelectCard({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;

    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : aiUi.glassColor;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : aiUi.borderColor.withValues(alpha: 0.05);
    final textColor =
        isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    final subTextColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.8)
        : aiUi.secondaryTextColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: isSelected ? aiUi.primaryShadow : aiUi.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                FluentIcons.flash_24_filled,
                color: isSelected ? Colors.white : theme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.proxies.autoSelect,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.proxies.autoSelectDescription,
                    style: TextStyle(fontSize: 11, color: subTextColor),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(FluentIcons.checkmark_24_filled, color: textColor, size: 20)
            else
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: aiUi.secondaryTextColor.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProxy extends ConsumerWidget {
  const _EmptyProxy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiUi = Theme.of(context).aiUi;
    final t = ref.watch(translationsProvider);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: aiUi.softBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.globe_24_regular,
              size: 36,
              color: aiUi.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            t.proxies.emptyProxiesMsg,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: aiUi.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.home.emptyProfilesMsg,
            style: TextStyle(
              fontSize: 13,
              color: aiUi.secondaryTextColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  final OutboundGroup group;
  final bool isConnected;
  final VoidCallback? onTest;

  const _GroupHeader({
    required this.group,
    required this.isConnected,
    this.onTest,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              group.tag,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _typeLabel(group.type, t),
            style: TextStyle(
              fontSize: 11,
              color: aiUi.secondaryTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (onTest != null)
            GestureDetector(
              onTap: onTest,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: aiUi.softBackgroundColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.flash_16_regular,
                      size: 12,
                      color: aiUi.secondaryTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.proxies.delayTestBtn,
                      style: TextStyle(
                        fontSize: 10,
                        color: aiUi.secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            t.proxies.lineCount(count: group.items.length.toString()),
            style: TextStyle(
              fontSize: 11,
              color: aiUi.secondaryTextColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _typeLabel(String type, TranslationsEn t) {
    switch (type.toLowerCase()) {
      case 'selector':
        return t.proxies.manualSelect;
      case 'urltest':
      case 'url_test':
        return t.proxies.autoTest;
      default:
        return type;
    }
  }
}

class _ProxyTile extends StatelessWidget {
  final OutboundProxy proxy;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProxyTile({
    required this.proxy,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final isLight = theme.brightness == Brightness.light;

    final bgColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : (isLight ? Colors.white : aiUi.glassColor);
    final borderColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.3)
        : aiUi.borderColor.withValues(alpha: 0.15);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: isSelected ? aiUi.primaryShadow : null,
        ),
        child: Row(
          children: [
            // 选中指示
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color:
                    isSelected ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            // 节点信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proxy.tag,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatType(proxy.type),
                    style: TextStyle(
                      fontSize: 11,
                      color: aiUi.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            // 延迟
            _DelayBadge(delay: proxy.delay),
          ],
        ),
      ),
    );
  }

  String _formatType(String type) {
    switch (type.toLowerCase()) {
      case 'shadowsocks':
        return 'SS';
      case 'vmess':
        return 'VMess';
      case 'vless':
        return 'VLESS';
      case 'trojan':
        return 'Trojan';
      case 'hysteria':
        return 'Hysteria';
      case 'hysteria2':
        return 'Hysteria2';
      case 'wireguard':
        return 'WireGuard';
      case 'tuic':
        return 'TUIC';
      default:
        return type.toUpperCase();
    }
  }
}

class _DelayBadge extends StatelessWidget {
  final int delay;
  const _DelayBadge({required this.delay});

  @override
  Widget build(BuildContext context) {
    if (delay <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '-',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      );
    }

    final Color color;
    if (delay < 200) {
      color = const Color(0xFF10B981);
    } else if (delay < 500) {
      color = const Color(0xFFEAB308);
    } else {
      color = const Color(0xFFEF4444);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${delay}ms',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
