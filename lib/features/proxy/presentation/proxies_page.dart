import 'dart:math' as math;
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/theme/motion.dart';
import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_service.dart';
import 'package:clashmiao/core/haptic/haptic_service.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/routing/application/offline_proxy_groups_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/proxy/application/optimistic_proxy_selections_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/domain/routing/model/node_display.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:clashmiao/features/proxy/application/proxies_sort_notifier.dart';
import 'package:clashmiao/features/proxy/application/row_order.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:clashmiao/shared/components/page_header.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:clashmiao/shared/navigation/selected_tab.dart';
import 'package:collection/collection.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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

  /// 每个分组上一次实际展示的行顺序（节点 tag）。测速进行中或手指按着列表时，
  /// 行顺序冻结在它上面，见 [stableRowOrder]。
  final Map<String, List<String>> _shownOrder = {};

  /// 上一次展示时的排序方式：用户换了排序方式就立即按新方式排，不冻结。
  ProxiesSort? _shownSort;

  /// 正按在列表上的手指数。
  int _pointersDown = 0;

  /// 冻结期间有一次被推迟的重排：最后一根手指抬起时重建一次把它补上。
  bool _reorderDeferred = false;

  /// 列表开始滚动时通知所有行：位移动画直接走到终点。滚动是手势，一旦开始
  /// 就没有「按看到的位置点击」需要维持了；不收掉的话，布局位置滚进缓存区、
  /// 父级不再绘制的行还挂着位移。
  final _SlideSnap _slideSnap = _SlideSnap();

  @override
  void dispose() {
    _slideSnap.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent _) => _pointersDown++;

  void _onPointerRelease(PointerEvent _) {
    _pointersDown = math.max(0, _pointersDown - 1);
    if (_pointersDown == 0 && _reorderDeferred && mounted) {
      setState(() => _reorderDeferred = false);
    }
  }

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
    final storedSelections = ref.watch(proxySelectionStoreProvider);
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

    // 只有实时分组里的 tag 是运行中内核真实存在的分组：选择、测速这类内核操作
    // 只能对它们发起。离线兜底（未连接，或已连接但实时分组还没到）只用于展示——
    // 它解析自配置文件，tag 不保证存在于运行时（真机验收 BUG-1：对离线的 `proxy`
    // 组发起选择 / 测速，内核报 not found）。
    final canOperateKernel = isConnected && isLiveData;

    // 过滤掉内部保留字分组，并把订阅原始 selector 与修复出的 proxy
    // selector 这类等价分组折叠成一个可操作的主分组。离线展示时叠加存储里的手选
    // （下次连接时重放的就是它），而不是配置文件里的静态默认值。
    final visibleRawGroups = collapseDuplicateGroups(
      rawGroups.where(isUserVisibleGroup).toList(),
    );
    final displayGroups = isLiveData
        ? visibleRawGroups
        : applyStoredSelections(visibleRawGroups, storedSelections);

    // 每个节点的延迟展示状态：测量中（保留旧值）> 超时 > 未确认（历史值）>
    // 实时值 > 缓存值（含历史值），规则见 [resolveNodeLatency]。「测量中」是分组级的：同一个
    // 节点可能出现在几个分组里，只有它在**这个**分组的在途轮次里还没出结果
    // 才算测量中。
    NodeLatency latencyOf(OutboundGroup group, OutboundProxy proxy) {
      final cached = cachedDelays[proxy.tag];
      return resolveNodeLatency(
        liveMs: proxy.delay,
        cachedMs: cached?.ms,
        cachedAt: cached?.measuredAt,
        testing: latencyState.isNodePending(group.tag, proxy.tag),
        timedOut: latencyState.timedOutNodes.contains(proxy.tag),
        unconfirmed: latencyState.unconfirmedNodes.contains(proxy.tag),
        now: now,
        cacheIsFallback: !isLiveData,
      );
    }

    final List<OutboundGroup> groups = [];
    // 分组 tag → 节点 tag → 展示状态。按分组分开存：两个分组共享同一个节点时，
    // 后一个分组不会覆盖前一个分组里这个节点的状态。
    final Map<String, Map<String, NodeLatency>> latenciesByGroup = {};
    // 带隐藏标记的节点与订阅信息条目（「官网地址：…」「剩余流量：…」）一律
    // 不展示。实时分组里信息条目已被构建器打上隐藏标记；离线分组解析自订阅
    // 配置，信息条目还在，用整份配置算出的排除集（与构建器同一口径）过滤。
    final infoExclusions = isLiveData
        ? const <String>{}
        : ref.watch(offlineInfoExclusionsProvider).valueOrNull ??
              const <String>{};
    for (final group in displayGroups) {
      final sortedItems = selectableGroupItems(group.items, infoExclusions);
      final latencies = latenciesByGroup[group.tag] = {
        for (final item in sortedItems) item.tag: latencyOf(group, item),
      };
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

      // 测速进行中、或手指按在列表上时，行顺序冻结在上一次展示的样子：结果
      // 一条条回来时列表不跟着跳，手指按下时指着的节点也不会被换走。测速结束
      // 且没有手指按着时才按排序规则重排一次（带位移动画）。用户刚换了排序
      // 方式则立即生效。
      final frozen =
          _shownSort == sortBy &&
          (_pointersDown > 0 || latencyState.isGroupTesting(group.tag));
      final orderedItems = stableRowOrder(
        sorted: sortedItems,
        keyOf: (item) => item.tag,
        shown: _shownOrder[group.tag],
        frozen: frozen,
      );
      if (frozen &&
          !const ListEquality<String>().equals(
            [for (final item in orderedItems) item.tag],
            [for (final item in sortedItems) item.tag],
          )) {
        _reorderDeferred = true;
      }
      _shownOrder[group.tag] = [for (final item in orderedItems) item.tag];

      final currentSelected = optimisticSelections[group.tag] ?? group.selected;

      groups.add(
        OutboundGroup(
          tag: group.tag,
          type: group.type,
          selected: currentSelected,
          items: orderedItems,
        ),
      );
    }
    _shownSort = sortBy;

    // 排除之后可能有整组为空（只有信息条目的分组）：主组取第一个还有条目的。
    final primaryGroup = primaryDisplayGroup(groups);

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
              // Header：与首页同一个 PageHeader（标题 24 sp、最小高 48 dp）。
              PageHeader(
                title: t.proxies.pageTitle,
                actions: [
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
                        primaryGroup != null && canDelayTestGroup(primaryGroup)
                        ? () => _testDelay(
                            context,
                            ref,
                            primaryGroup,
                            isConnected,
                            canOperateKernel,
                          )
                        : () {
                            AppToast.info(context, t.proxies.emptyProxiesMsg);
                          },
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

                          // 每行用节点 tag 作 key，并告诉列表 key 现在在第几行：
                          // 重排时行的 element 跟着节点走，而不是留在原位置换成
                          // 别的节点。这样按下时指着 A，即使之后 A 挪了位置，
                          // 抬起时选中的仍是 A；位移动画也靠它认出「同一行」。
                          final indexByKey = <String, int>{
                            if (autoProxy != null) _kAutoCardKey: 0,
                            for (var i = 0; i < otherProxies.length; i++)
                              _nodeRowKey(otherProxies[i].tag):
                                  i + autoCardCount,
                          };

                          return Listener(
                            onPointerDown: _onPointerDown,
                            onPointerUp: _onPointerRelease,
                            onPointerCancel: _onPointerRelease,
                            child:
                                NotificationListener<ScrollStartNotification>(
                                  onNotification: (_) {
                                    _slideSnap.snap();
                                    return false;
                                  },
                                  child: ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 120),
                                    itemCount:
                                        otherProxies.length + autoCardCount,
                                    // 重绘边界与语义序号由行自己加在位移盒里面（见
                                    // [_ReorderSlide]）：位移盒必须是列表的直接子节点
                                    // ——列表把点交给它、由它按绘制位置判断命中；它
                                    // 在 paint 里发现位置变化，挪动时自己得重绘。
                                    addRepaintBoundaries: false,
                                    addSemanticIndexes: false,
                                    findChildIndexCallback: (key) =>
                                        key is ValueKey<String>
                                        ? indexByKey[key.value]
                                        : null,
                                    itemBuilder: (ctx, index) {
                                      if (autoProxy != null && index == 0) {
                                        // 固定在第 0 行，不做位移动画。
                                        return IndexedSemantics(
                                          key: const ValueKey(_kAutoCardKey),
                                          index: index,
                                          child: RepaintBoundary(
                                            child: _AutoSelectCard(
                                              isSelected:
                                                  group.selected ==
                                                  autoProxy.tag,
                                              onTap: () => _selectProxy(
                                                context,
                                                ref,
                                                group.tag,
                                                autoProxy.tag,
                                                isConnected,
                                                canOperateKernel,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                      final proxy =
                                          otherProxies[index - autoCardCount];
                                      final isSelected =
                                          group.selected == proxy.tag;
                                      return _ReorderSlide(
                                        key: ValueKey(_nodeRowKey(proxy.tag)),
                                        semanticIndex: index,
                                        snap: _slideSnap,
                                        child: _ProxyTile(
                                          proxy: proxy,
                                          isSelected: isSelected,
                                          latency:
                                              latenciesByGroup[group.tag]?[proxy
                                                  .tag] ??
                                              const NodeLatency(
                                                LatencyDisplayState.untested,
                                              ),
                                          onTap: () => _selectProxy(
                                            context,
                                            ref,
                                            group.tag,
                                            proxy.tag,
                                            isConnected,
                                            canOperateKernel,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
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
    bool canOperateKernel,
  ) {
    final t = ref.read(translationsProvider);
    if (!isConnected) {
      AppToast.info(context, t.proxies.connectBeforeSwitch);
      return;
    }
    if (!canOperateKernel) {
      // 已连接但实时分组还没到：眼前的分组来自配置文件，tag 不一定存在于运行
      // 时，绝不拿它去调内核。
      AppToast.info(context, t.proxies.groupsLoading);
      return;
    }
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
    // 手选流程（先写存储 → 带 expectedAttempt 调内核 → 非 stale 失败回滚存储）
    // 在 ProxySelectionService 里，见该文件的说明。
    final attempt = ref.read(connectionControllerProvider).attempt;
    unawaited(
      ref
          .read(proxySelectionServiceProvider)
          .select(groupTag, outboundTag, expectedAttempt: attempt)
          .then((result) {
            if (result is! SelectionFailed) return;
            optimisticNotifier.revert(groupTag, previousSelection);
            // 技术细节只进应用日志；用户看到的是类型化的本地化文案。
            logAppFailure(
              'proxies.select $groupTag -> $outboundTag',
              'SelectionFailed(${result.code}, ${result.message})',
            );
            if (!context.mounted) return;
            AppToast.error(context, t.proxies.switchFailed);
          }),
    );
  }

  Future<void> _testDelay(
    BuildContext context,
    WidgetRef ref,
    OutboundGroup group,
    bool isConnected,
    bool canOperateKernel,
  ) async {
    if (!canDelayTestGroup(group)) return;
    final t = ref.read(translationsProvider);
    if (!isConnected) {
      AppToast.error(context, t.proxies.connectBeforeTest);
      return;
    }
    if (!canOperateKernel) {
      AppToast.info(context, t.proxies.groupsLoading);
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
    } catch (error, st) {
      // 技术细节（PlatformException 等）只进日志。
      logAppFailure('proxies.latencyTest ${group.tag}', error, st);
      if (!context.mounted) return;
      AppToast.error(context, t.proxies.testFailed);
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
                .animateWithMotion(context)
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

/// 自动选择卡在线路列表里的 key。
const String _kAutoCardKey = 'auto-card';

/// 节点行在线路列表里的 key（带前缀，不与自动选择卡的 key 撞）。
String _nodeRowKey(String tag) => 'node:$tag';

/// 列表重排时让行从原位置滑到新位置（FLIP）：在 paint 里比较这一行在列表里的
/// 位置与上一帧的位置，变了就先画在原位置，再用动画把位移收回到零。
///
/// 行必须带稳定的 key、列表要提供 `findChildIndexCallback`，重排后 element 才是
/// 「同一行」。位移盒必须是列表（sliver）的直接子节点：列表关掉自带的重绘边界
/// 与语义序号（它们会包在位移盒外面），由这里加在位移盒**里面**——
/// - 列表逐个把点交给直接子节点，位移盒按**绘制位置**判断命中，动画途中看到
///   哪一行、点到的就是哪一行；包在外面的节点会先按布局位置把点拒掉。
/// - 行内容在自己的重绘边界里：位移只让这个很薄的盒子重绘、换图层偏移，
///   行内容不重新绘制；测速结果更新也只重绘那一行。
///
/// 系统开了「减少动画」时不做位移，直接出现在新位置。
class _ReorderSlide extends StatefulWidget {
  const _ReorderSlide({
    super.key,
    required this.semanticIndex,
    required this.snap,
    required this.child,
  });

  /// 这一行在列表里的序号（读屏的「第几项」），等同列表自带的语义序号。
  final int semanticIndex;

  /// 列表开始滚动时触发：位移动画直接走到终点。
  final _SlideSnap snap;
  final Widget child;

  @override
  State<_ReorderSlide> createState() => _ReorderSlideState();
}

class _ReorderSlideState extends State<_ReorderSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.medium,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SlideBox(
    controller: _controller,
    snap: widget.snap,
    enabled: !Motion.reduced(context),
    child: IndexedSemantics(
      index: widget.semanticIndex,
      child: RepaintBoundary(child: widget.child),
    ),
  );
}

class _SlideBox extends SingleChildRenderObjectWidget {
  const _SlideBox({
    required this.controller,
    required this.snap,
    required this.enabled,
    required super.child,
  });

  final AnimationController controller;
  final _SlideSnap snap;
  final bool enabled;

  @override
  _RenderSlideBox createRenderObject(BuildContext context) =>
      _RenderSlideBox(controller, snap, enabled);

  @override
  void updateRenderObject(BuildContext context, _RenderSlideBox renderObject) {
    renderObject
      ..controller = controller
      ..snap = snap
      ..enabled = enabled;
  }
}

class _RenderSlideBox extends RenderProxyBox {
  _RenderSlideBox(this._controller, this._snap, this._enabled);

  _SlideSnap _snap;
  set snap(_SlideSnap value) {
    if (identical(value, _snap)) return;
    if (attached) _snap.removeListener(_snapToEnd);
    _snap = value;
    if (attached) _snap.addListener(_snapToEnd);
  }

  /// 位移动画直接走到终点：画在、点在布局位置上。同时忘掉上一次绘制的位置：
  /// 滚动期间没被绘制的行（在缓存区里）之后再画出来时，不从一个早已过时的
  /// 位置滑过来。
  void _snapToEnd() {
    _lastOffset = null;
    if (_from == 0 && !_startPending) return;
    _from = 0;
    _startPending = false;
    _controller.stop();
    markNeedsPaint();
  }

  AnimationController _controller;
  set controller(AnimationController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
  }

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (!value) {
      _from = 0;
      _controller.stop();
    }
    markNeedsPaint();
  }

  /// 上一次绘制时这一行在列表里的位置。
  double? _lastOffset;

  /// 动画起点的位移（原位置 − 新位置）；动画从它收回到 0。
  double _from = 0;

  /// 本帧刚发现位置变化、动画要到下一帧才启动：这一帧按完整位移绘制。
  bool _startPending = false;

  double get _dy => _startPending
      ? _from
      : _from * (1 - Motion.standard.transform(_controller.value));

  /// 这一行在列表（sliver）里的布局位置：沿父链找到列表直接子节点的 parentData。
  double? _layoutOffset() {
    RenderObject? node = this;
    while (node != null) {
      final data = node.parentData;
      if (data is SliverMultiBoxAdaptorParentData) return data.layoutOffset;
      node = node.parent;
    }
    return null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
    _snap.addListener(_snapToEnd);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _snap.removeListener(_snapToEnd);
    super.detach();
  }

  /// 当前实际绘制的位移（减少动画时为 0）。
  double get _paintDy => _enabled ? _dy : 0;

  // 绘制位移同样作用于坐标换算与命中测试：动画途中看到的、点到的是同一处。
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _paintDy, 0, 1);
  }

  /// 按**绘制位置**判断点没点中这一行。默认实现按布局位置先做边界检查：行
  /// 画在原位置、布局已在新位置时，点在看到的那一行上会被它拒掉（被吞掉），
  /// 点在布局位置上又落到一处空白。列表不做边界检查、逐个询问直接子节点
  /// （从后往前，与绘制的上下层一致），所以这里按绘制位置回答。
  ///
  /// 命中与绘制必须一致：列表只绘制布局范围与绘制区间相交的行，布局位置
  /// 落在缓存区（滚出可视范围、或挪到可视范围外）的行根本没画出来，这里
  /// 同口径直接拒绝，不能凭位移去截获可见行的点击。
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_paintedByParent()) return false;
    if (!size.contains(position - Offset(0, _paintDy))) return false;
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  /// 列表（sliver）这一帧会不会绘制这一行：与
  /// `RenderSliverMultiBoxAdaptor.paint` 的裁剪条件相同——布局区间
  /// [位置, 位置 + 高度) 与绘制区间 (0, remainingPaintExtent) 相交。
  bool _paintedByParent() {
    final sliver = parent;
    if (sliver is! RenderSliverMultiBoxAdaptor) return true;
    final delta = sliver.childMainAxisPosition(this);
    return delta < sliver.constraints.remainingPaintExtent &&
        delta + size.height > 0;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _paintDy),
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final current = _layoutOffset();
    final last = _lastOffset;
    if (_enabled &&
        current != null &&
        last != null &&
        (current - last).abs() > 0.5) {
      // 从「上一帧看到的位置」（原布局位置 + 当时的位移）滑到新位置。
      _from = last + _dy - current;
      _startPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!attached || !_startPending) return;
        _startPending = false;
        _controller.forward(from: 0);
      });
    }
    _lastOffset = current;
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, offset.translate(0, _paintDy));
  }
}

/// 列表开始滚动的广播：各行的位移盒监听它，收到就把位移动画直接走到终点。
class _SlideSnap extends ChangeNotifier {
  void snap() => notifyListeners();
}

class _AutoSelectCard extends HookConsumerWidget {
  const _AutoSelectCard({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 整张卡合并为一个节点，带选中语义（与节点行一致）。
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: _buildCard(context, ref),
      ),
    );
  }

  Widget _buildCard(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;

    // 两行字选中与否同色、都不叠 alpha：选中靠品牌色描边、实心图标块与对勾
    // 表达（与节点行同一套）。原来选中时标题用 primary、说明用 80% primary，
    // 压在半透明卡片 + 品牌晕染上，浅色主题下标题只有 4.48:1、11 sp 说明更低，
    // 达不到小字 4.5:1。说明用不透明的 onSurfaceVariant（与延迟列中性色同源）。
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = theme.colorScheme.onSurfaceVariant;
    final accent = theme.colorScheme.primary;

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
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
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
                Icon(FluentIcons.checkmark_24_filled, color: accent, size: 20)
              else
                Icon(
                  FluentIcons.chevron_right_24_regular,
                  size: 16,
                  color: aiUi.secondaryTextColor,
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
/// 行高基准 [rowHeight]（含描边，选中与否一样高），字体放大时自然增高；行距 8 dp
/// 只来自外层这一处 padding。
///
/// 旗帜只在左侧旗帜区出现一次：名称里开头的旗帜已被搬走（见 [NodeDisplay]），
/// 推断不出国家时用中性地球图标，而不是随便挂一面旗。
class _ProxyTile extends ConsumerWidget {
  /// 延迟列最小宽度（spec：右对齐列宽约 64 dp）。
  static const double _latencyColumnMinWidth = 64;

  /// 正常字号下的行高（spec 68–72 dp），**含**描边。之前最小高度 72 加在描边
  /// 里面，真机量出来 74（选中 75）dp。
  @visibleForTesting
  static const double rowHeight = 70;

  /// 名称 / 协议两行的行高倍数。名称用的是自带的 Emoji 字体做首选字体，它的
  /// 行度量很高（真机单行名称约 33 dp），不固定倍数行高就由字体决定、无从控制。
  static const double _lineHeight = 1.3;

  /// 行里除名称与延迟列外的固定宽度：旗帜区 36 + 间距 12 + 间距 8 + 间距 8 +
  /// 对勾占位 18。
  static const double _rowFixedWidth = 36 + 12 + 8 + 8 + 18;

  /// 延迟挪到下一行时，名称列（也是延迟换行的宽度）之外的固定宽度：旗帜区 36
  /// + 间距 12 + 间距 8 + 对勾占位 18。
  static const double _stackedFixedWidth = 36 + 12 + 8 + 18;

  /// 延迟列留在右侧时，名称至少要保有的行宽比例；不够就把延迟挪到下一行。
  ///
  /// 预算按有效上限 `65000ms` 留位置（见 [LatencyLabel.budget]）。取 35%：
  /// 360 dp、1.0× 的常见手机上名称约 110 dp 以上、延迟仍在右侧同一行；大字号或
  /// 窄屏下名称会被挤到这条线以下时才挪行。
  static const double _minNameFraction = 0.35;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aiUi = theme.aiUi;
    final primary = theme.colorScheme.primary;
    // 展示名只用于显示；选择、缓存一律用 proxy.tag。
    final display = NodeDisplay.parse(proxy.tag);
    // 名字只有一面旗帜（或干脆为空）：旗帜已在左侧旗帜区出现一次，名称位
    // 放一个中性占位，而不是把旗帜再写一遍。
    final hasLabel = display.label.isNotEmpty;
    final t = ref.watch(translationsProvider);
    final label = hasLabel ? display.label : t.general.unknown;

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
                  // 描边画在卡片内侧：最小高度扣掉上下描边，整行（含描边）正好
                  // [rowHeight]，选中（1.5 dp）与未选中（1 dp）一样高。
                  constraints: BoxConstraints(
                    minHeight: rowHeight - 2 * (isSelected ? 1.5 : 1),
                  ),
                  child: Padding(
                    // 选中描边 1.5 dp、未选中 1 dp：差的 0.5 dp 从内边距里扣掉，
                    // 选中与否内容都不位移。
                    padding: EdgeInsets.symmetric(
                      horizontal: isSelected ? 13.5 : 14,
                      vertical: isSelected ? 9.5 : 10,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // 布局只按「这套字体 / 缩放 / 语言下所有延迟状态的最大
                        // 尺寸」定，不按当前结果定：测速从 `—` 变成长数字、超时
                        // 文字、再回到测量中，名称宽度、行高、后面节点的位置都
                        // 不变（见 [LatencyLabel.budget]）。
                        //
                        // 预算宽度放在右侧会把名称挤到行宽的 [_minNameFraction]
                        // 以下时（大字号 / 窄屏 / 长的本地化文字），延迟整行挪到
                        // 协议下面（允许在词间换行），名称拿回整行宽度；两种布局
                        // 都按预算预留位置。不缩小字号。
                        final inlineBudget = LatencyLabel.budget(context, t);
                        final latencySlotWidth = math.max(
                          _latencyColumnMinWidth,
                          inlineBudget.width,
                        );
                        final stacked =
                            constraints.maxWidth -
                                _rowFixedWidth -
                                latencySlotWidth <
                            constraints.maxWidth * _minNameFraction;
                        final stackedBudget = stacked
                            ? LatencyLabel.budget(
                                context,
                                t,
                                wrapWidth:
                                    constraints.maxWidth - _stackedFixedWidth,
                              )
                            : null;
                        return Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Center(
                                child: _FlagGlyph(display: display),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: _lineHeight,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                      fontWeight: FontWeight.w600,
                                      color: hasLabel
                                          ? theme.colorScheme.onSurface
                                          : aiUi.secondaryTextColor,
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
                                      height: _lineHeight,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                      color: aiUi.secondaryTextColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (stackedBudget != null) ...[
                                    const SizedBox(height: 2),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: stackedBudget.height,
                                      ),
                                      child: LatencyLabel(
                                        state: latency.state,
                                        ms: latency.ms,
                                        textAlign: TextAlign.start,
                                        wrap: true,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!stacked) ...[
                              const SizedBox(width: 8),
                              Container(
                                constraints: BoxConstraints(
                                  minWidth: latencySlotWidth,
                                  minHeight: inlineBudget.height,
                                ),
                                alignment: AlignmentDirectional.centerEnd,
                                child: LatencyLabel(
                                  state: latency.state,
                                  ms: latency.ms,
                                ),
                              ),
                            ],
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
                        );
                      },
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
