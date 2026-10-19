import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/latency_clock.dart';
import 'package:clashmiao/domain/routing/application/proxy_delay_cache_notifier.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:clashmiao/domain/routing/model/node_display.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 进入 connected 后等这么久再自动测当前组（给内核与分组流一点起来的时间）。
const Duration kLatencyWarmupDelay = Duration(seconds: 2);

/// 同一个分组两次自动测速的最小间隔。手动测速不受它约束。
const Duration kLatencyAutoCooldown = Duration(seconds: 30);

/// 一轮测速最长等多久：到点就收尾，没结果的节点标为超时。
const Duration kLatencyRoundTimeout = Duration(seconds: 10);

/// 协调器对外暴露的状态：哪些组在测、哪些节点上一轮没测出结果。
class LatencyTestState {
  const LatencyTestState({
    this.testingGroups = const {},
    this.timedOutNodes = const {},
  });

  /// 正在测速的分组 tag。
  final Set<String> testingGroups;

  /// 最近一轮测完仍没有有效结果的节点 tag（展示为「超时」）。
  final Set<String> timedOutNodes;

  bool get isTesting => testingGroups.isNotEmpty;
  bool isGroupTesting(String groupTag) => testingGroups.contains(groupTag);

  LatencyTestState copyWith({
    Set<String>? testingGroups,
    Set<String>? timedOutNodes,
  }) => LatencyTestState(
    testingGroups: testingGroups ?? this.testingGroups,
    timedOutNodes: timedOutNodes ?? this.timedOutNodes,
  );

  @override
  bool operator ==(Object other) =>
      other is LatencyTestState &&
      _setEquals(other.testingGroups, testingGroups) &&
      _setEquals(other.timedOutNodes, timedOutNodes);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(testingGroups),
    Object.hashAllUnordered(timedOutNodes),
  );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

class _Round {
  _Round(this.group, this.baseline, {required this.manual});

  final String group;

  /// 开测时各节点的实时延迟。`urlTest()` 返回 void，结果只能从分组流里观察：
  /// 某个节点的值和开测时不同，就说明它在本轮里出了结果。
  final Map<String, int> baseline;
  final bool manual;
  final Completer<void> done = Completer<void>();
  Timer? timeout;
  Object? error;
  StackTrace? stackTrace;
}

/// 自动测速协调器：决定**什么时候**对哪个分组发起 `urlTest`，并把结果收尾。
///
/// - 进入 connected 后 [kLatencyWarmupDelay] 且目标组可用时，测当前（主）组；
/// - 打开代理页时，已连接且该组没有数据、或数据超过 [kLatencyStaleAfter]，测一次；
/// - 同组自动测速 [kLatencyAutoCooldown] 内去重；
/// - 手动测速绕过冷却，但在途时复用同一个任务；
/// - 断开、重连、切订阅取消旧任务；
/// - 一轮的完成条件 = 组内所有节点都有了本轮结果，或 [kLatencyRoundTimeout]。
///
/// 依赖全部通过构造函数注入（回调），时间只读 [Timer] 与 `now`，所以可以用
/// fake_async 完整驱动。Riverpod 接线见 [latencyTestCoordinatorProvider]。
class LatencyTestCoordinator extends StateNotifier<LatencyTestState> {
  LatencyTestCoordinator({
    required Future<void> Function(String groupTag) urlTest,
    required List<OutboundGroup> Function() liveGroups,
    required Map<String, CachedDelay> Function() cache,
    required void Function(Map<String, int> msByTag, DateTime at)
    recordMeasured,
    required DateTime Function() now,
  }) : _urlTest = urlTest,
       _liveGroups = liveGroups,
       _cache = cache,
       _recordMeasured = recordMeasured,
       _now = now,
       super(const LatencyTestState());

  final Future<void> Function(String groupTag) _urlTest;
  final List<OutboundGroup> Function() _liveGroups;
  final Map<String, CachedDelay> Function() _cache;
  final void Function(Map<String, int> msByTag, DateTime at) _recordMeasured;
  final DateTime Function() _now;

  bool _connected = false;
  Timer? _warmup;
  bool _warmupPending = false;
  final Map<String, _Round> _rounds = {};
  final Map<String, DateTime> _lastStart = {};

  // --------------------------------------------------------------- 外部事件

  /// 连接状态变化。任何变化（断开、重连）都先取消旧任务、清空状态；
  /// 变为已连接后重新走 2 s 预热。
  void onConnectionChanged(bool connected) {
    _connected = connected;
    _reset();
    if (connected) {
      _warmup = Timer(kLatencyWarmupDelay, _onWarmup);
    }
  }

  /// 切换了订阅：旧订阅的在途任务与超时标记都作废。
  void onProfileChanged() => _reset();

  /// 分组流推来了新数据。
  void onGroups(List<OutboundGroup> groups) {
    if (!_connected) return;
    if (_warmupPending) {
      final target = primaryVisibleGroup(groups);
      if (target != null && canDelayTestGroup(target)) {
        _warmupPending = false;
        requestAuto(target.tag);
      }
    }
    for (final round in List<_Round>.of(_rounds.values)) {
      final group = _find(groups, round.group);
      if (group != null && _isRoundComplete(round, group)) _finish(round);
    }
  }

  /// 用户打开了代理页。
  void onProxiesPageOpened() {
    if (!_connected) return;
    final group = primaryVisibleGroup(_liveGroups());
    if (group == null || !canDelayTestGroup(group)) return;
    if (!_needsTest(group)) return;
    requestAuto(group.tag);
  }

  /// 自动测速入口：在途或冷却内都直接忽略。
  void requestAuto(String groupTag) {
    if (!_connected) return;
    if (_rounds.containsKey(groupTag)) return;
    final last = _lastStart[groupTag];
    if (last != null && _now().difference(last) < kLatencyAutoCooldown) return;
    _start(groupTag, manual: false);
  }

  /// 手动测速：绕过冷却；该组已有在途任务就复用它。未连接时什么都不做。
  ///
  /// 返回的 Future 在本轮收尾（或被取消）时完成；内核调用失败则抛出。
  Future<void> manualTest(String groupTag) async {
    if (!_connected) return;
    final round = _rounds[groupTag] ?? _start(groupTag, manual: true);
    await round.done.future;
    final error = round.error;
    if (error != null && round.manual) {
      Error.throwWithStackTrace(error, round.stackTrace ?? StackTrace.empty);
    }
  }

  // --------------------------------------------------------------- 内部

  void _onWarmup() {
    _warmup = null;
    final group = primaryVisibleGroup(_liveGroups());
    if (group == null || !canDelayTestGroup(group)) {
      // 目标组还没数据：等分组流推来再测。
      _warmupPending = true;
      return;
    }
    requestAuto(group.tag);
  }

  /// 该组的数据是否需要重测：没有任何实时数据，或最新的测量时间超过 5 分钟
  /// （没有测量时间的历史值同样算过期）。
  bool _needsTest(OutboundGroup group) {
    final cache = _cache();
    DateTime? newest;
    var hasData = false;
    for (final item in _testableItems(group)) {
      if (!isMeasurableDelay(item.delay)) continue;
      hasData = true;
      final at = cache[item.tag]?.measuredAt;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    if (!hasData || newest == null) return true;
    return _now().difference(newest) > kLatencyStaleAfter;
  }

  _Round _start(String groupTag, {required bool manual}) {
    final live = _find(_liveGroups(), groupTag);
    final round = _Round(groupTag, {
      for (final item in live?.items ?? const <OutboundProxy>[])
        item.tag: item.delay,
    }, manual: manual);
    _rounds[groupTag] = round;
    _lastStart[groupTag] = _now();

    final ownTags = {
      for (final item in live?.items ?? const <OutboundProxy>[]) item.tag,
    };
    _emit(
      state.copyWith(
        testingGroups: {...state.testingGroups, groupTag},
        timedOutNodes: state.timedOutNodes.difference(ownTags),
      ),
    );

    round.timeout = Timer(kLatencyRoundTimeout, () => _finish(round));
    Future<void>.sync(() => _urlTest(groupTag)).then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!identical(_rounds[groupTag], round)) return;
        round.error = error;
        round.stackTrace = stackTrace;
        _end(round, markTimeouts: false);
      },
    );
    return round;
  }

  bool _isRoundComplete(_Round round, OutboundGroup group) {
    final items = _testableItems(group);
    if (items.isEmpty) return false;
    return items.every((item) => item.delay != (round.baseline[item.tag] ?? 0));
  }

  void _finish(_Round round) => _end(round, markTimeouts: true);

  /// 收尾一轮：取消超时定时器、把结果写进缓存、更新状态、放行等待者。
  void _end(_Round round, {required bool markTimeouts}) {
    if (!identical(_rounds[round.group], round)) return;
    _rounds.remove(round.group);
    round.timeout?.cancel();

    final group = _find(_liveGroups(), round.group);
    final timedOut = <String>{};
    final measured = <String, int>{};
    if (markTimeouts && group != null) {
      for (final item in _testableItems(group)) {
        if (isMeasurableDelay(item.delay)) {
          measured[item.tag] = item.delay;
        } else {
          timedOut.add(item.tag);
        }
      }
    }
    if (measured.isNotEmpty) _recordMeasured(measured, _now());

    _emit(
      state.copyWith(
        testingGroups: {...state.testingGroups}..remove(round.group),
        timedOutNodes: {...state.timedOutNodes, ...timedOut},
      ),
    );
    if (!round.done.isCompleted) round.done.complete();
  }

  /// 取消一切：不写缓存、不标超时，放行所有等待者。
  void _reset() {
    _warmup?.cancel();
    _warmup = null;
    _warmupPending = false;
    for (final round in _rounds.values) {
      round.timeout?.cancel();
      if (!round.done.isCompleted) round.done.complete();
    }
    _rounds.clear();
    _lastStart.clear();
    _emit(const LatencyTestState());
  }

  void _emit(LatencyTestState next) {
    if (!mounted) return;
    state = next;
  }

  @override
  void dispose() {
    _warmup?.cancel();
    for (final round in _rounds.values) {
      round.timeout?.cancel();
      if (!round.done.isCompleted) round.done.complete();
    }
    _rounds.clear();
    super.dispose();
  }
}

/// 参与「是否测完」判断的节点：叶子节点，排除订阅标记隐藏的节点与嵌套分组
/// （它们的延迟不是这一轮 `urlTest` 的结果）。
Iterable<OutboundProxy> _testableItems(OutboundGroup group) =>
    group.items.where(
      (item) => !NodeDisplay.isHidden(item.tag) && !isGroupProxyType(item.type),
    );

OutboundGroup? _find(List<OutboundGroup> groups, String tag) {
  for (final group in groups) {
    if (group.tag == tag) return group;
  }
  return null;
}

/// 协调器的 Riverpod 接线。
///
/// 代理页常驻（`IndexedStack`），它 watch 这个 provider，协调器就与连接状态
/// 同生共死；单独读它的测试也能完整工作。
final latencyTestCoordinatorProvider =
    StateNotifierProvider<LatencyTestCoordinator, LatencyTestState>((ref) {
      final coordinator = LatencyTestCoordinator(
        urlTest: (groupTag) => ref.read(boxServiceProvider).urlTest(groupTag),
        liveGroups: () =>
            ref.read(outboundGroupsProvider).valueOrNull ??
            const <OutboundGroup>[],
        cache: () => ref.read(proxyDelayCacheProvider),
        recordMeasured: (msByTag, at) => ref
            .read(proxyDelayCacheProvider.notifier)
            .recordMeasured(msByTag, at: at),
        now: ref.read(latencyClockProvider),
      );
      ref.listen<bool>(
        isConnectedProvider,
        (_, connected) => coordinator.onConnectionChanged(connected),
        fireImmediately: true,
      );
      ref.listen<AsyncValue<List<OutboundGroup>>>(
        outboundGroupsProvider,
        (_, next) => coordinator.onGroups(next.valueOrNull ?? const []),
      );
      ref.listen<String?>(
        activeProfileProvider.select((profile) => profile.valueOrNull?.id),
        (previous, next) {
          // previous 为空是首次加载出订阅，不是「切订阅」。
          if (previous != null && previous != next) {
            coordinator.onProfileChanged();
          }
        },
      );
      return coordinator;
    });
