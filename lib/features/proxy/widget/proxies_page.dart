import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/proxy/state/optimistic_proxy_selections_notifier.dart';
import 'package:clashmiao/features/proxy/state/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/features/proxy/state/proxy_selection_store_notifier.dart';
import 'package:clashmiao/features/proxy/state/proxies_sort_notifier.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _urlTestType = 'urltest';

final _proxyTestExecutingProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

String _normalizeGroupType(String type) {
  final trimmed = type.trim().toLowerCase();
  return trimmed.replaceAll('-', '').replaceAll('_', '');
}

class ProxiesPage extends ConsumerStatefulWidget {
  const ProxiesPage({super.key, this.debugOpenProxyNameModal = false});

  final bool debugOpenProxyNameModal;

  @override
  ConsumerState<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends ConsumerState<ProxiesPage> {
  bool _debugProxyNameModalOpened = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final isConnected = ref.watch(isConnectedProvider);
    final sortBy = ref.watch(proxiesSortProvider);
    final optimisticSelections = ref.watch(optimisticProxySelectionsProvider);
    final cachedDelays = ref.watch(proxyDelayCacheProvider);
    final isTestingProxies = ref.watch(_proxyTestExecutingProvider);

    ref.listen<AsyncValue<List<OutboundGroup>>>(outboundGroupsProvider, (
      _,
      next,
    ) {
      final groups = next.valueOrNull;
      if (groups == null || groups.isEmpty) return;
      ref.read(proxyDelayCacheProvider.notifier).persistFromGroups(groups);
    });

    if (widget.debugOpenProxyNameModal && !_debugProxyNameModalOpened) {
      _debugProxyNameModalOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showProxyNameModal(context, '香港 01 | SS');
      });
    }

    // 已连接时优先使用实时数据，否则用离线解析
    final liveGroups = ref.watch(outboundGroupsProvider);
    final offlineGroups = ref.watch(offlineProxyGroupsProvider);
    final offlineFallback = offlineGroups.valueOrNull ?? [];
    final currentLiveGroups = liveGroups.valueOrNull;
    if (currentLiveGroups != null && currentLiveGroups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(proxyDelayCacheProvider.notifier)
            .persistFromGroups(currentLiveGroups);
      });
    }

    // 是否真的在用实时分组数据——只有这个为 false 时才需要拿本地缓存的历史
    // 延迟兜底展示。已连接且实时数据非空时必须信任实时数据本身：这个分支下
    // 哪怕某个节点延迟还是 0（没测出来），也不能用缓存里冻结的旧数值顶替，
    // 否则会显示一个永远不变的假数字（"每次都是同一个数字"那个 bug 的根因）。
    bool isLiveData = false;
    List<OutboundGroup> rawGroups;
    if (isConnected) {
      rawGroups = liveGroups.when<List<OutboundGroup>>(
        data: (g) {
          final hasData = g.any((group) => group.items.isNotEmpty);
          isLiveData = hasData;
          return hasData ? g : offlineFallback;
        },
        loading: () => offlineFallback,
        error: (_, __) => offlineFallback,
      );
    } else {
      rawGroups = offlineFallback;
    }

    // 过滤掉内部保留字分组，并把订阅原始 selector 与修复出的 proxy
    // selector 这类等价分组折叠成一个可操作的主分组。
    final collapsedGroups = _collapseDuplicateGroups(
      rawGroups.where(_isUserVisibleGroup).toList(),
    );
    final List<OutboundGroup> visibleRawGroups = isLiveData
        ? collapsedGroups
        : _applyCachedDelays(collapsedGroups, cachedDelays);
    final List<OutboundGroup> groups = [];
    for (final group in visibleRawGroups) {
      final sortedItems = group.items.where(_isVisibleProxy).toList();
      // 分组类型优先：嵌套代理组（selector/urltest）排在普通代理节点前面，
      // 组内再按各自排序规则（名称/延迟）细排——不这样做的话，嵌套代理组
      // 和普通节点会按名称/延迟随意混排在一起。`unsorted` 保持原始顺序，
      // 不做任何重排（跟改动前行为一致）。
      if (sortBy == ProxiesSort.name) {
        sortedItems.sort((a, b) {
          final groupFirst = _compareGroupFirst(a, b);
          if (groupFirst != 0) return groupFirst;
          return _proxyDisplayName(a.tag).compareTo(_proxyDisplayName(b.tag));
        });
      } else if (sortBy == ProxiesSort.delay) {
        sortedItems.sort((a, b) {
          final groupFirst = _compareGroupFirst(a, b);
          if (groupFirst != 0) return groupFirst;
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

    final primaryGroup = groups.firstOrNull;

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
                        onTap:
                            primaryGroup != null && _canDelayTest(primaryGroup)
                            ? () => _testDelay(
                                context,
                                ref,
                                primaryGroup,
                                isConnected,
                              )
                            : () {
                                AppToast.info(
                                  context,
                                  t.proxies.emptyProxiesMsg,
                                );
                              },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Content
              Expanded(
                child: primaryGroup == null
                    ? const _EmptyProxy()
                    : Builder(
                        builder: (context) {
                          final group = primaryGroup;
                          final autoProxy =
                              group.items.firstWhereOrNull(
                                (e) =>
                                    _normalizeGroupType(e.type) == _urlTestType,
                              ) ??
                              group.items.firstWhereOrNull(
                                (e) => e.tag.toLowerCase() == 'auto',
                              );
                          final otherProxies = group.items
                              .where((e) => e != autoProxy)
                              .toList();

                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: otherProxies.length + 1,
                            itemBuilder: (ctx, index) {
                              if (index == 0) {
                                return _AutoSelectCard(
                                  isSelected:
                                      autoProxy != null &&
                                      group.selected == autoProxy.tag,
                                  onTap: () {
                                    if (autoProxy == null) {
                                      AppToast.error(
                                        context,
                                        t.proxies.emptyProxiesMsg,
                                      );
                                      return;
                                    }
                                    _selectProxy(
                                      context,
                                      ref,
                                      group.tag,
                                      autoProxy.tag,
                                      isConnected,
                                    );
                                  },
                                );
                              }
                              final proxy = otherProxies[index - 1];
                              final isSelected = group.selected == proxy.tag;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ProxyTile(
                                  proxy: proxy,
                                  isSelected: isSelected,
                                  showLoading: isTestingProxies,
                                  onTap: () => _selectProxy(
                                    context,
                                    ref,
                                    group.tag,
                                    proxy.tag,
                                    isConnected,
                                  ),
                                ),
                              );
                            },
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
      // 参照代理切换的触觉反馈：点击即触发，不等待 selectOutbound 的异步结果
      // （跟 connect/disconnect 那两处既有触点的 fire-and-forget 风格一致）。
      unawaited(ref.read(hapticServiceProvider).lightImpact());
      final optimisticNotifier = ref.read(
        optimisticProxySelectionsProvider.notifier,
      );
      // 记录点击前的乐观值快照，native 切换失败时用它回滚，而不是把错误节点
      // 永久留在 UI 上。
      final previousSelection =
          ref.read(optimisticProxySelectionsProvider)[groupTag];
      optimisticNotifier.update(groupTag, outboundTag);
      ref
          .read(boxServiceProvider)
          .selectOutbound(groupTag, outboundTag)
          .then((_) {
            // 只有 native 真正切换成功才记为"用户手选的节点"，供下次重连重放
            // （见 ProxySelectionStoreNotifier 注释：selector 的选中状态只活在
            // 运行中的实例内存里，重连会用 config 的静态 default 重新起）。
            unawaited(
              ref
                  .read(proxySelectionStoreProvider.notifier)
                  .persist(groupTag, outboundTag),
            );
            // Toast can be annoying on fast switches, removed or keep brief
            // AppToast.success(context, t.proxies.switchedTo(name: outboundTag));
          })
          .catchError((e) {
            optimisticNotifier.revert(groupTag, previousSelection);
            if (!context.mounted) return;
            AppToast.error(
              context,
              t.proxies.switchToFailed(error: e.toString()),
            );
          });
    } else {
      AppToast.info(context, t.proxies.connectBeforeSwitch);
    }
  }

  Future<void> _testDelay(
    BuildContext context,
    WidgetRef ref,
    OutboundGroup group,
    bool isConnected,
  ) async {
    if (!_canDelayTest(group)) return;
    final t = ref.read(translationsProvider);
    if (!isConnected) {
      AppToast.error(context, '请连接后测速');
      return;
    }

    final testing = ref.read(_proxyTestExecutingProvider.notifier);
    if (testing.state) return;

    testing.state = true;
    try {
      // fire-and-forget，跟 _selectProxy／connect/disconnect 两处既有触点一致：
      // 触觉反馈绝不能 await 阻塞真正的测速调用（尤其是没有 mock 平台通道的
      // 测试环境下，await 会让这个 Future 永远挂起，拖死 urlTest）。
      unawaited(ref.read(hapticServiceProvider).lightImpact());
      await Future.wait([
        ref.read(boxServiceProvider).urlTest(group.tag),
        Future<void>.delayed(const Duration(milliseconds: 1500)),
      ]);
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, '${t.failure.unexpected}: $error');
    } finally {
      testing.state = false;
    }
  }

  bool _canDelayTest(OutboundGroup group) {
    if (group.items.isEmpty) return false;

    final groupType = _normalizeGroupType(group.type);
    return groupType == _urlTestType ||
        groupType == 'selector' ||
        groupType == 'select';
  }
}

bool _isUserVisibleGroup(OutboundGroup group) {
  final tag = group.tag.toUpperCase();
  return tag != 'GLOBAL' && tag != 'DIRECT' && tag != 'REJECT';
}

List<OutboundGroup> _collapseDuplicateGroups(List<OutboundGroup> groups) {
  final proxy = groups.firstWhereOrNull(
    (group) => group.tag == 'proxy' && group.items.isNotEmpty,
  );
  if (proxy == null) return groups;

  final proxyItems = _itemTagSet(proxy);
  if (proxyItems.isEmpty) return groups;

  return groups.where((group) {
    if (identical(group, proxy) || group.tag == proxy.tag) return true;
    if (!_isSelectableGroup(group)) return true;
    return !_sameItemTags(proxyItems, _itemTagSet(group));
  }).toList();
}

bool _isSelectableGroup(OutboundGroup group) {
  return _isGroupProxyType(group.type);
}

/// 判断一个 outbound 的 type 是否为"分组类型"（selector/urltest），而不是
/// shadowsocks/vmess 这类叶子代理节点。分组类型优先排序（见
/// `_compareGroupFirst`）和 `_isSelectableGroup` 共用同一套判定标准。
bool _isGroupProxyType(String type) {
  final normalized = _normalizeGroupType(type);
  return normalized == 'selector' ||
      normalized == 'select' ||
      normalized == _urlTestType;
}

/// 排序时"分组类型优先"的比较器：嵌套代理组排在普通代理节点前面，
/// 两者类型相同时返回 0，交给调用方按名称/延迟继续细排。
int _compareGroupFirst(OutboundProxy a, OutboundProxy b) {
  final aIsGroup = _isGroupProxyType(a.type);
  final bIsGroup = _isGroupProxyType(b.type);
  if (aIsGroup == bIsGroup) return 0;
  return aIsGroup ? -1 : 1;
}

Set<String> _itemTagSet(OutboundGroup group) {
  return group.items
      .map((item) => item.tag)
      .where((tag) => tag.isNotEmpty)
      .toSet();
}

bool _sameItemTags(Set<String> left, Set<String> right) {
  if (left.length != right.length) return false;
  return left.containsAll(right);
}

bool _isVisibleProxy(OutboundProxy proxy) {
  return !proxy.tag.contains('§hide§');
}

String _proxyDisplayName(String tag) {
  final markerIndex = tag.indexOf('§');
  return (markerIndex == -1 ? tag : tag.substring(0, markerIndex)).trimRight();
}

List<OutboundGroup> _applyCachedDelays(
  List<OutboundGroup> groups,
  Map<String, int> cachedDelays,
) {
  if (cachedDelays.isEmpty) return groups;

  return groups.map((group) {
    return OutboundGroup(
      tag: group.tag,
      type: group.type,
      selected: group.selected,
      items: group.items.map((item) {
        if (item.delay > 0) return item;
        final cachedDelay = cachedDelays[item.tag];
        return cachedDelay != null && cachedDelay > 0
            ? item.copyWith(delay: cachedDelay)
            : item;
      }).toList(),
    );
  }).toList();
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
    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
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
    final t = ref.watch(translationsProvider);
    return Center(child: Text(t.proxies.emptyProxiesMsg));
  }
}

class _ProxyTile extends StatelessWidget {
  final OutboundProxy proxy;
  final bool isSelected;
  final bool showLoading;
  final VoidCallback onTap;

  const _ProxyTile({
    required this.proxy,
    required this.isSelected,
    required this.showLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final delay = proxy.delay;
    final delayColor = _getDelayColor(delay);
    final displayName = _proxyDisplayName(proxy.tag);

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showProxyNameModal(context, displayName),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: aiUi.glassColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : aiUi.borderColor.withValues(alpha: 0.05),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? aiUi.primaryShadow : aiUi.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: aiUi.softBackgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _getCountryFlag(displayName),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Emoji',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: aiUi.softBackgroundColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: aiUi.borderColor.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Text(
                          _formatType(proxy.type).toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'Monospace',
                            color: aiUi.secondaryTextColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (showLoading)
                  _DelayTestingBars(color: theme.colorScheme.primary)
                else ...[
                  Text(
                    delay != 0 ? (delay > 65000 ? '×' : '${delay}ms') : '--',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: delayColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(_getSignalIcon(delay), color: delayColor, size: 16),
                ],
              ],
            ),
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

class _DelayTestingBars extends StatelessWidget {
  const _DelayTestingBars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          return Container(
                width: 3.5,
                height: 6 + (index * 4.0),
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [color.withValues(alpha: 0.4), color],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              )
              .animate(onPlay: (controller) => controller.repeat())
              .scaleY(
                begin: 0.1,
                end: 1,
                duration: 800.ms,
                delay: (index * 120).ms,
                curve: Curves.elasticOut,
              )
              .fadeIn(delay: (index * 120).ms)
              .shimmer(delay: (index * 120).ms, duration: 1500.ms);
        }),
      ),
    );
  }
}

void _showProxyNameModal(BuildContext context, String name) {
  showAiUiModal<void>(
    context: context,
    builder: (context) {
      final localizations = MaterialLocalizations.of(context);
      return AiUiModalWrapper(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).aiUi.secondaryTextColor,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(localizations.okButtonLabel),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}

String _getCountryFlag(String name) {
  final nameLower = name.toLowerCase();

  const rules = [
    (flag: '🇭🇰', keywords: ['hk', 'hong kong', 'hongkong', '香港']),
    (
      flag: '🇨🇳',
      keywords: ['tw', 'taiwan', 'tai wan', '台湾', '台北', 'taipei', 'roc'],
    ),
    (flag: '🇲🇴', keywords: ['mo', 'macau', 'macao', '澳门']),
    (flag: '🇸🇬', keywords: ['sg', 'singapore', '新加坡', '狮城']),
    (
      flag: '🇯🇵',
      keywords: ['jp', 'japan', '日本', '东京', '大阪', 'tokyo', 'osaka'],
    ),
    (
      flag: '🇺🇸',
      keywords: ['us', 'usa', 'united states', 'america', '美国', '美'],
    ),
    (
      flag: '🇬🇧',
      keywords: ['uk', 'united kingdom', 'britain', '英国', '伦敦', 'london'],
    ),
    (
      flag: '🇰🇷',
      keywords: ['kr', 'korea', 'south korea', '韩国', '首尔', 'seoul'],
    ),
    (flag: '🇩🇪', keywords: ['de', 'germany', 'deutschland', '德国']),
    (flag: '🇫🇷', keywords: ['fr', 'france', '法国']),
    (flag: '🇨🇦', keywords: ['ca', 'canada', '加拿大']),
    (flag: '🇦🇺', keywords: ['au', 'australia', '澳大利亚', '澳洲']),
    (flag: '🇷🇺', keywords: ['ru', 'russia', '俄罗斯']),
    (flag: '🇮🇳', keywords: ['in', 'india', '印度']),
    (flag: '🇳🇱', keywords: ['nl', 'netherlands', '荷兰']),
    (
      flag: '🇨🇳',
      keywords: [
        'cn',
        'china',
        '中国',
        '内地',
        '江苏',
        '北京',
        '上海',
        'beijing',
        'shanghai',
      ],
    ),
    (flag: '🇲🇾', keywords: ['my', 'malaysia', '马来西亚']),
    (flag: '🇹🇭', keywords: ['th', 'thailand', '泰国']),
    (flag: '🇻🇳', keywords: ['vn', 'vietnam', '越南']),
    (flag: '🇵🇭', keywords: ['ph', 'philippines', '菲律宾']),
    (flag: '🇮🇩', keywords: ['id', 'indonesia', '印尼']),
    (flag: '🇧🇷', keywords: ['br', 'brazil', '巴西']),
    (flag: '🇮🇹', keywords: ['it', 'italy', '意大利']),
    (flag: '🇪🇸', keywords: ['es', 'spain', '西班牙']),
    (flag: '🇹🇷', keywords: ['tr', 'turkey', '土耳其']),
    (flag: '🇺🇦', keywords: ['ua', 'ukraine', '乌克兰']),
    (flag: '🇨🇭', keywords: ['ch', 'switzerland', '瑞士']),
    (flag: '🇸🇪', keywords: ['se', 'sweden', '瑞典']),
    (flag: '🇳🇴', keywords: ['no', 'norway', '挪威']),
    (flag: '🇫🇮', keywords: ['fi', 'finland', '芬兰']),
    (flag: '🇩🇰', keywords: ['dk', 'denmark', '丹麦']),
    (flag: '🇧🇪', keywords: ['be', 'belgium', '比利时']),
    (flag: '🇮🇪', keywords: ['ie', 'ireland', '爱尔兰']),
    (flag: '🇦🇹', keywords: ['at', 'austria', '奥地利']),
    (flag: '🇵🇱', keywords: ['pl', 'poland', '波兰']),
    (flag: '🇭🇺', keywords: ['hu', 'hungary', '匈牙利']),
    (flag: '🇨🇿', keywords: ['cz', 'czech', '捷克']),
    (flag: '🇷🇴', keywords: ['ro', 'romania', '罗马尼亚']),
    (flag: '🇬🇷', keywords: ['gr', 'greece', '希腊']),
    (flag: '🇵🇹', keywords: ['pt', 'portugal', '葡萄牙']),
    (flag: '🇿🇦', keywords: ['za', 'south africa', '南非']),
    (flag: '🇦🇷', keywords: ['ar', 'argentina', '阿根廷']),
    (flag: '🇲🇽', keywords: ['mx', 'mexico', '墨西哥']),
    (flag: '🇨🇱', keywords: ['cl', 'chile', '智利']),
    (flag: '🇨🇴', keywords: ['co', 'colombia', '哥伦比亚']),
    (flag: '🇵🇪', keywords: ['pe', 'peru', '秘鲁']),
    (
      flag: '🇦🇪',
      keywords: ['ae', 'uae', 'united arab emirates', '阿联酋', '迪拜', 'dubai'],
    ),
    (flag: '🇮🇱', keywords: ['il', 'israel', '以色列']),
    (flag: '🇸🇦', keywords: ['sa', 'saudi arabia', '沙特']),
    (flag: '🇧🇬', keywords: ['bg', 'bulgaria', '保加利亚']),
    (flag: '🇭🇷', keywords: ['hr', 'croatia', '克罗地亚']),
    (flag: '🇮🇷', keywords: ['ir', 'iran', '伊朗']),
    (flag: '🇰🇵', keywords: ['kp', 'north korea', '朝鲜']),
  ];

  for (final rule in rules) {
    for (final keyword in rule.keywords) {
      if (keyword.length <= 2) {
        if (RegExp('(^|[^a-z])$keyword([^a-z]|\$)').hasMatch(nameLower)) {
          return rule.flag;
        }
      } else if (nameLower.contains(keyword)) {
        return rule.flag;
      }
    }
  }

  return '🌐';
}

Color _getDelayColor(int delay) {
  if (delay == 0) return Colors.grey.withValues(alpha: 0.5);
  if (delay > 65000) return Colors.red;
  if (delay < 250) return const Color(0xFF10B981);
  if (delay < 600) return Colors.orangeAccent;
  return Colors.red;
}

IconData _getSignalIcon(int delay) {
  if (delay == 0) return FluentIcons.wifi_1_24_regular;
  if (delay > 65000) return FluentIcons.error_circle_24_regular;
  if (delay < 250) return FluentIcons.wifi_1_24_filled;
  if (delay < 600) return FluentIcons.wifi_warning_24_regular;
  return FluentIcons.wifi_off_24_regular;
}
