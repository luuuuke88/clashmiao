import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/application/latency_test_coordinator.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/proxy/application/optimistic_proxy_selections_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/domain/routing/model/node_display.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesPage extends ConsumerStatefulWidget {
  const ProxiesPage({super.key, this.debugOpenProxyNameModal = false});

  final bool debugOpenProxyNameModal;

  @override
  ConsumerState<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends ConsumerState<ProxiesPage> {
  bool _debugProxyNameModalOpened = false;

  @override
  void initState() {
    super.initState();
    // 代理页常驻在 IndexedStack 里，initState 早于用户真正「打开」它；这里只
    // 处理「启动即停在代理页」（CLASHMIAO_INITIAL_TAB）的情形，其余靠下面
    // build 里对 selectedTabProvider 的监听。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(selectedTabProvider) == AppTab.proxies) {
        ref.read(latencyTestCoordinatorProvider.notifier).onProxiesPageOpened();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final isConnected = ref.watch(isConnectedProvider);
    final sortBy = ref.watch(proxiesSortProvider);
    final optimisticSelections = ref.watch(optimisticProxySelectionsProvider);
    final cachedDelays = ref.watch(proxyDelayCacheProvider);
    // watch 它同时让协调器随页面常驻：连接后 2 s 的自动测速不依赖用户看着这页。
    final latencyState = ref.watch(latencyTestCoordinatorProvider);
    final now = ref.watch(latencyClockProvider)();

    ref.listen<int>(selectedTabProvider, (previous, next) {
      if (next == AppTab.proxies && previous != next) {
        ref.read(latencyTestCoordinatorProvider.notifier).onProxiesPageOpened();
      }
    });

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

    // 是否真的在用实时分组数据——只有这个为 false 时才允许拿本地缓存的历史
    // 延迟兜底展示。已连接且实时数据非空时必须信任实时数据本身：这个分支下
    // 哪怕某个节点延迟还是 0（没测出来），也不能用缓存里冻结的旧数值顶替，
    // 否则会显示一个永远不变的假数字（"每次都是同一个数字"那个 bug 的根因）。
    var isLiveData = false;
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
    final visibleRawGroups = collapseDuplicateGroups(
      rawGroups.where(isUserVisibleGroup).toList(),
    );

    // 每个节点的延迟展示状态：实时值 > 测量中 > 超时 > 缓存值（含历史值），
    // 规则见 [resolveNodeLatency]。
    NodeLatency latencyOf(OutboundGroup group, OutboundProxy proxy) {
      final cached = cachedDelays[proxy.tag];
      return resolveNodeLatency(
        liveMs: proxy.delay,
        cachedMs: cached?.ms,
        cachedAt: cached?.measuredAt,
        testing: latencyState.isGroupTesting(group.tag),
        timedOut: latencyState.timedOutNodes.contains(proxy.tag),
        now: now,
        cacheIsFallback: !isLiveData,
      );
    }

    final List<OutboundGroup> groups = [];
    final Map<String, NodeLatency> latencies = {};
    for (final group in visibleRawGroups) {
      final sortedItems = group.items
          .where((item) => !NodeDisplay.isHidden(item.tag))
          .toList();
      for (final item in sortedItems) {
        latencies[item.tag] = latencyOf(group, item);
      }
      // 分组类型优先：嵌套代理组（selector/urltest）排在普通代理节点前面，
      // 组内再按各自排序规则（名称/延迟）细排——不这样做的话，嵌套代理组
      // 和普通节点会按名称/延迟随意混排在一起。`unsorted` 保持原始顺序，
      // 不做任何重排（跟改动前行为一致）。
      if (sortBy == ProxiesSort.name) {
        sortedItems.sort((a, b) {
          final groupFirst = _compareGroupFirst(a, b);
          if (groupFirst != 0) return groupFirst;
          return NodeDisplay.stripSuffix(
            a.tag,
          ).compareTo(NodeDisplay.stripSuffix(b.tag));
        });
      } else if (sortBy == ProxiesSort.delay) {
        sortedItems.sort((a, b) {
          final groupFirst = _compareGroupFirst(a, b);
          if (groupFirst != 0) return groupFirst;
          final ai = latencies[a.tag]?.ms ?? 0;
          final bi = latencies[b.tag]?.ms ?? 0;
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

    // 背景晕染统一由 ShellPage 底下那层 BrandBackdrop 画，页面自己保持透明。
    return Scaffold(
      backgroundColor: Colors.transparent,
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
                        tooltip: t.proxies.sortTooltip,
                        onTap: () {
                          showAiUiModal<void>(
                            context: context,
                            builder: (context) => const ProxiesSortModal(),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      _HeaderButton(
                        icon: FluentIcons.flash_24_regular,
                        loading:
                            primaryGroup != null &&
                            latencyState.isGroupTesting(primaryGroup.tag),
                        tooltip:
                            primaryGroup != null &&
                                latencyState.isGroupTesting(primaryGroup.tag)
                            ? t.proxies.delaySemantics.testing
                            : t.proxies.delayTestTooltip,
                        onTap:
                            primaryGroup != null &&
                                canDelayTestGroup(primaryGroup)
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
                                    normalizeGroupType(e.type) ==
                                    kUrlTestGroupType,
                              ) ??
                              group.items.firstWhereOrNull(
                                (e) => e.tag.toLowerCase() == 'auto',
                              );
                          final otherProxies = group.items
                              .where((e) => e != autoProxy)
                              .toList();

                          // 自动选择卡只在订阅里真有自动选择组时才构建：没有
                          // 就不画一张点了只会报错的卡（假入口）。有的话它
                          // 占列表第 0 位，其余节点下标整体后移一位。
                          final autoCardCount = autoProxy == null ? 0 : 1;

                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            itemCount: otherProxies.length + autoCardCount,
                            itemBuilder: (ctx, index) {
                              if (autoProxy != null && index == 0) {
                                return _AutoSelectCard(
                                  isSelected: group.selected == autoProxy.tag,
                                  onTap: () => _selectProxy(
                                    context,
                                    ref,
                                    group.tag,
                                    autoProxy.tag,
                                    isConnected,
                                  ),
                                );
                              }
                              final proxy = otherProxies[index - autoCardCount];
                              final isSelected = group.selected == proxy.tag;
                              return _ProxyTile(
                                proxy: proxy,
                                isSelected: isSelected,
                                latency:
                                    latencies[proxy.tag] ??
                                    const NodeLatency(
                                      LatencyDisplayState.untested,
                                    ),
                                onTap: () => _selectProxy(
                                  context,
                                  ref,
                                  group.tag,
                                  proxy.tag,
                                  isConnected,
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
      final previousSelection = ref.read(
        optimisticProxySelectionsProvider,
      )[groupTag];
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
          .catchError((Object e) {
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
    if (!canDelayTestGroup(group)) return;
    final t = ref.read(translationsProvider);
    if (!isConnected) {
      AppToast.error(context, t.proxies.connectBeforeTest);
      return;
    }

    try {
      // fire-and-forget，跟 _selectProxy／connect/disconnect 两处既有触点一致：
      // 触觉反馈绝不能 await 阻塞真正的测速调用（尤其是没有 mock 平台通道的
      // 测试环境下，await 会让这个 Future 永远挂起，拖死 urlTest）。
      unawaited(ref.read(hapticServiceProvider).lightImpact());
      // 该组已有在途测速（含自动测速）时协调器会复用它，不会重复发起。
      await ref
          .read(latencyTestCoordinatorProvider.notifier)
          .manualTest(group.tag);
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(context, '${t.failure.unexpected}: $error');
    }
  }
}

/// 排序时「分组类型优先」的比较器：嵌套代理组排在普通代理节点前面，
/// 两者类型相同时返回 0，交给调用方按名称/延迟继续细排。
int _compareGroupFirst(OutboundProxy a, OutboundProxy b) {
  final aIsGroup = isGroupProxyType(a.type);
  final bIsGroup = isGroupProxyType(b.type);
  if (aIsGroup == bIsGroup) return 0;
  return aIsGroup ? -1 : 1;
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
  final String? tooltip;
  final bool loading;

  const _HeaderButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      icon: icon,
      onTap: onTap,
      tooltip: tooltip,
      loading: loading,
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

    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final subTextColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.8)
        : aiUi.secondaryTextColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: GlassCard(
          borderRadius: 14,
          padding: const EdgeInsets.all(14),
          borderColor: isSelected ? theme.colorScheme.primary : null,
          borderWidth: isSelected ? 1.5 : 1,
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
                Icon(
                  FluentIcons.checkmark_24_filled,
                  color: textColor,
                  size: 20,
                )
              else
                Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 16,
                  color: aiUi.secondaryTextColor.withValues(alpha: 0.5),
                ),
            ],
          ),
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

/// 代理页的一行节点。
///
/// 布局（从左到右）：旗帜区 36 dp → 名称 + 协议（两行）→ 延迟列（最小 64 dp、
/// 右对齐）→ 18 dp 对勾占位（选中才画，但**始终占位**，免得文字位移）。
/// 行高基准 72 dp，字体放大时自然增高；行距 8 dp 只来自外层这一处 padding。
///
/// 旗帜只在左侧旗帜区出现一次：名称里开头的旗帜已被搬走（见 [NodeDisplay]），
/// 推断不出国家时用中性地球图标，而不是随便挂一面旗。
class _ProxyTile extends StatelessWidget {
  final OutboundProxy proxy;
  final bool isSelected;
  final NodeLatency latency;
  final VoidCallback onTap;

  const _ProxyTile({
    required this.proxy,
    required this.isSelected,
    required this.latency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final primary = theme.colorScheme.primary;
    // 展示名只用于显示；选择、缓存一律用 proxy.tag。
    final display = NodeDisplay.parse(proxy.tag);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: isSelected,
          child: GlassCard(
            borderRadius: 14,
            padding: EdgeInsets.zero,
            borderColor: isSelected ? primary : null,
            borderWidth: isSelected ? 1.5 : 1,
            child: Ink(
              color: isSelected ? primary.withValues(alpha: 0.08) : null,
              child: InkWell(
                onTap: onTap,
                onLongPress: () => _showProxyNameModal(
                  context,
                  NodeDisplay.stripSuffix(proxy.tag),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    // 选中描边 1.5 dp、未选中 1 dp：差的 0.5 dp 从内边距里扣掉，
                    // 选中与否内容都不位移。
                    padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? 13.5 : 14,
                      vertical: isSelected ? 9.5 : 10,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Center(child: _FlagGlyph(display: display)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                display.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                  fontFamily: 'Emoji',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatType(proxy.type),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: aiUi.secondaryTextColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 64),
                          alignment: AlignmentDirectional.centerEnd,
                          child: LatencyLabel(
                            state: latency.state,
                            ms: latency.ms,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: isSelected
                              ? Icon(
                                  FluentIcons.checkmark_24_filled,
                                  size: 18,
                                  color: primary,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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

/// 左侧旗帜区：有旗帜画旗帜，没有就画中性地球图标。
class _FlagGlyph extends StatelessWidget {
  const _FlagGlyph({required this.display});

  final NodeDisplay display;

  @override
  Widget build(BuildContext context) {
    final flag = display.flag;
    if (flag == null) {
      return ExcludeSemantics(
        child: Icon(
          FluentIcons.globe_24_regular,
          size: 24,
          color: Theme.of(context).aiUi.secondaryTextColor,
        ),
      );
    }
    return ExcludeSemantics(
      child: Text(
        flag,
        style: const TextStyle(fontSize: 24, fontFamily: 'Emoji'),
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
