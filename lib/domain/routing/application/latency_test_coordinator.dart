import 'dart:async';
import 'dart:math' as math;

import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:hooks_riverpod/legacy.dart';

/// 进入 connected 后等这么久再自动测当前组（给内核与分组流一点起来的时间）。
const Duration kLatencyWarmupDelay = Duration(seconds: 2);

/// 同一个分组两次自动测速的最小间隔。手动测速不受它约束。
const Duration kLatencyAutoCooldown = Duration(seconds: 30);

/// 内核对一个分组测速时的并发数，与每一路探测最长占用的时间（锁定内核的
/// `TCPTimeout`，15 s）。节点多的分组要分批测：一批 10 个全是死的，就要占满
/// 15 s 下一批才开始——25 个节点最坏要 45 s，末批可达的节点前面两批不结束就
/// 没机会开始测。
const int kLatencyKernelConcurrency = 10;
const Duration kLatencyKernelWave = Duration(seconds: 15);

/// 在内核最坏耗时之外留给分组流推送与调度的余量。
const Duration kLatencyRoundMargin = Duration(seconds: 2);

/// 单轮预算的封顶：节点再多也不让用户等过 60 s。
const Duration kLatencyRoundCap = Duration(seconds: 60);

/// 一批（至多 [kLatencyKernelConcurrency] 个节点）的一轮测速预算。
const Duration kLatencyRoundTimeout = Duration(seconds: 17);

/// [nodeCount] 个节点的一轮测速最长等多久：`ceil(n / 10) × 15 s + 2 s`，封顶
/// [kLatencyRoundCap]。到点仍没有有效结果的节点判为失败（超时）；超过封顶
/// 才测完的结果由 [LatencyTestCoordinator] 在分组流里继续接收。
Duration latencyRoundTimeoutFor(int nodeCount) {
  final batches = math.max(
    1,
    (nodeCount + kLatencyKernelConcurrency - 1) ~/ kLatencyKernelConcurrency,
  );
  final needed = kLatencyKernelWave * batches + kLatencyRoundMargin;
  return needed > kLatencyRoundCap ? kLatencyRoundCap : needed;
}

/// 协调器对外暴露的状态：哪些组在测、在测的组里哪些节点还没有本轮结果、
/// 哪些节点上一轮没测出结果、哪些节点上一轮没确认而保留着旧值。
class LatencyTestState {
  const LatencyTestState({
    this.testingGroups = const {},
    this.pendingNodes = const {},
    this.timedOutNodes = const {},
    this.unconfirmedNodes = const {},
  });

  /// 正在测速的分组 tag。
  final Set<String> testingGroups;

  /// 在测分组 tag → 该组里**还没有本轮结果**的节点 tag。
  ///
  /// 按分组记：同一个节点可能同时出现在几个分组里，A 组在测不代表 B 组在测。
  /// 已经出了本轮结果的节点不在这里，界面可以直接展示新值。
  final Map<String, Set<String>> pendingNodes;

  /// 最近一轮测完仍没有有效结果的节点 tag（展示为「超时」）：本轮确认测
  /// 失败的，或到点没确认、手上也没有任何旧值的；还有不在任何轮次里时实时值
  /// 从有效变成无效的（内核后台检测测失败、删了测速历史）。之后实时值变成
  /// 有效的新结果才会被移出。
  final Set<String> timedOutNodes;

  /// 最近一轮到点收尾时**没确认**出结果、但**实时值仍然有效**的节点 tag
  /// （展示为「历史值」，带这个实时旧值，不显示超时）。只有缓存里有旧数字、
  /// 实时没有值的节点不在这里——那是失败，在 [timedOutNodes]。
  ///
  /// 内核回复 `urlTest` 时测试只是**开始**了，结果陆续写进分组流；实时值到点
  /// 仍没变化的节点无从判断是没测完还是恰好测出同一个数，所以既不能当新结果，
  /// 也不能判超时。实时值之后一变就会被移出：变成另一个有效值是新结果；变成
  /// 无效值（0 或超时哨兵）是迟到的失败，改记入 [timedOutNodes] 并写进失败缓存。
  final Set<String> unconfirmedNodes;

  bool get isTesting => testingGroups.isNotEmpty;
  bool isGroupTesting(String groupTag) => testingGroups.contains(groupTag);

  /// [nodeTag] 在 [groupTag] 这一轮里是否还在等结果。
  bool isNodePending(String groupTag, String nodeTag) =>
      pendingNodes[groupTag]?.contains(nodeTag) ?? false;

  /// [nodeTag] 是否在任何一个在测分组里还在等结果（首页胶囊不区分分组）。
  bool isNodePendingInAnyGroup(String nodeTag) =>
      pendingNodes.values.any((nodes) => nodes.contains(nodeTag));

  LatencyTestState copyWith({
    Set<String>? testingGroups,
    Map<String, Set<String>>? pendingNodes,
    Set<String>? timedOutNodes,
    Set<String>? unconfirmedNodes,
  }) => LatencyTestState(
    testingGroups: testingGroups ?? this.testingGroups,
    pendingNodes: pendingNodes ?? this.pendingNodes,
    timedOutNodes: timedOutNodes ?? this.timedOutNodes,
    unconfirmedNodes: unconfirmedNodes ?? this.unconfirmedNodes,
  );

  @override
  bool operator ==(Object other) =>
      other is LatencyTestState &&
      _setEquals(other.testingGroups, testingGroups) &&
      _mapOfSetsEquals(other.pendingNodes, pendingNodes) &&
      _setEquals(other.timedOutNodes, timedOutNodes) &&
      _setEquals(other.unconfirmedNodes, unconfirmedNodes);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(testingGroups),
    Object.hashAllUnordered([
      for (final e in pendingNodes.entries)
        Object.hash(e.key, Object.hashAllUnordered(e.value)),
    ]),
    Object.hashAllUnordered(timedOutNodes),
    Object.hashAllUnordered(unconfirmedNodes),
  );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _mapOfSetsEquals(Map<String, Set<String>> a, Map<String, Set<String>> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    final other = b[e.key];
    if (other == null || !_setEquals(e.value, other)) return false;
  }
  return true;
}

class _Round {
  _Round(this.group, this.baseline);

  final String group;

  /// 开测时各节点的实时延迟。`urlTest()` 返回 void，结果只能从分组流里观察：
  /// 某个节点的值和开测时不同，就说明它在本轮里出了结果。
  final Map<String, int> baseline;

  /// 本轮已确认出了结果的节点（值与开测基线不同）。只有它们会在收尾时
  /// 刷新测量时间；实时值仍有效但没确认的节点保留原来的值与测量时间，展示为
  /// 历史值——它可能还没测完，也可能恰好被重测成同一个毫秒数，无从分辨，所以
  /// 既不把旧值记成新结果，也不判它超时。实时没有有效值的节点收尾时判失败。
  final Set<String> confirmed = {};

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
/// - 一轮的完成条件 = 组内所有节点都有了本轮结果，或到 [latencyRoundTimeoutFor] 的预算。
///   收尾时只刷新本轮**确认**出了结果的节点的测量时间；实时没有有效值的节点
///   （测失败 / 超时）一律标超时并把失败写进缓存，不论缓存里有没有旧的成功值；
///   只有实时值仍有效、没确认的节点保留为历史值。
///
/// 依赖全部通过构造函数注入（回调），时间只读 [Timer] 与 `now`，所以可以用
/// fake_async 完整驱动。Riverpod 接线见 [latencyTestCoordinatorProvider]。
class LatencyTestCoordinator extends StateNotifier<LatencyTestState> {
  LatencyTestCoordinator({
    required this._urlTest,
    required this._liveGroups,
    required this._cache,
    required this._recordMeasured,
    required this._recordFailed,
    required this._now,
  }) : super(const LatencyTestState());

  final Future<void> Function(String groupTag) _urlTest;
  final List<OutboundGroup> Function() _liveGroups;
  final Map<String, CachedDelay> Function() _cache;
  final void Function(Map<String, int> msByTag, DateTime at) _recordMeasured;
  final void Function(Set<String> tags, DateTime at) _recordFailed;
  final DateTime Function() _now;

  bool _connected = false;
  Timer? _warmup;
  bool _warmupPending = false;
  final Map<String, _Round> _rounds = {};
  final Map<String, DateTime> _lastStart = {};

  /// 被标为超时或未确认的节点 → 标记那一刻的实时延迟。实时值之后变了，说明
  /// 出了新的测量结果（比如订阅自带的自动选择组在后台测过），标记随之撤掉。
  final Map<String, int> _markedAt = {};

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

  /// 参与「是否测完」判断的节点：实时分组里的叶子节点，排除带隐藏标记的节点
  /// 与嵌套分组——它们的延迟不是这一轮 `urlTest` 的结果。订阅信息条目已经由
  /// 构建器打上隐藏标记、不在内核的分组里（整份订阅只有信息条目时按保护留下，
  /// 内核也会测它们），所以这里不再另算排除集。
  Iterable<OutboundProxy> _testableItems(OutboundGroup group) =>
      selectableGroupItems(
        group.items,
        const {},
      ).where((item) => !isGroupProxyType(item.type));

  int _testableCount(OutboundGroup? group) =>
      group == null ? 0 : _testableItems(group).length;

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
    _releaseTimeouts(groups);
    for (final round in List<_Round>.of(_rounds.values)) {
      final group = _find(groups, round.group);
      if (group == null) continue;
      _confirm(round, group);
      if (_isRoundComplete(round, group)) {
        _finish(round);
      } else {
        _emit(
          state.copyWith(
            pendingNodes: {
              ...state.pendingNodes,
              round.group: _pendingOf(round, group),
            },
          ),
        );
      }
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

  /// 自动测速入口：在途或冷却内都直接忽略。内核异常由这一轮的手动等待者
  /// 接收，自动入口自己不关心。
  void requestAuto(String groupTag) {
    if (!_connected) return;
    if (_rounds.containsKey(groupTag)) return;
    final last = _lastStart[groupTag];
    if (last != null && _now().difference(last) < kLatencyAutoCooldown) return;
    _start(groupTag);
  }

  /// 手动测速：绕过冷却；该组已有在途任务（包括自动发起的）就复用它。
  /// 未连接时什么都不做。
  ///
  /// 返回的 Future 在本轮收尾（或被取消）时完成；这一轮的内核调用失败则
  /// 抛出该异常——不论这一轮最初是自动还是手动发起的，每个手动等待者都会
  /// 收到。
  Future<void> manualTest(String groupTag) async {
    if (!_connected) return;
    final round = _rounds[groupTag] ?? _start(groupTag);
    await round.done.future;
    final error = round.error;
    if (error != null) {
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

  _Round _start(String groupTag) {
    final live = _find(_liveGroups(), groupTag);
    final round = _Round(groupTag, {
      for (final item in live?.items ?? const <OutboundProxy>[])
        item.tag: item.delay,
    });
    _rounds[groupTag] = round;
    _lastStart[groupTag] = _now();

    final ownTags = {
      for (final item in live?.items ?? const <OutboundProxy>[]) item.tag,
    };
    ownTags.forEach(_markedAt.remove);
    _emit(
      state.copyWith(
        testingGroups: {...state.testingGroups, groupTag},
        pendingNodes: {
          ...state.pendingNodes,
          groupTag: live == null ? const {} : _pendingOf(round, live),
        },
        timedOutNodes: state.timedOutNodes.difference(ownTags),
        unconfirmedNodes: state.unconfirmedNodes.difference(ownTags),
      ),
    );

    round.timeout = Timer(
      latencyRoundTimeoutFor(_testableCount(live)),
      () => _finish(round),
    );
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

  /// 把值与开测基线不同的节点记为本轮已确认。确认是累积的：一个节点出过
  /// 结果，后面的分组事件不会再把它变回「没结果」。
  void _confirm(_Round round, OutboundGroup group) {
    for (final item in _testableItems(group)) {
      if (item.delay != (round.baseline[item.tag] ?? 0)) {
        round.confirmed.add(item.tag);
      }
    }
  }

  Set<String> _pendingOf(_Round round, OutboundGroup group) => {
    for (final item in _testableItems(group))
      if (!round.confirmed.contains(item.tag)) item.tag,
  };

  bool _isRoundComplete(_Round round, OutboundGroup group) {
    final items = _testableItems(group);
    if (items.isEmpty) return false;
    return items.every((item) => round.confirmed.contains(item.tag));
  }

  /// 每个节点在分组流里最近一次的实时延迟（同一节点出现在几个分组里时，有一处
  /// 有效就取有效的）。用来发现「有效 → 无效」：内核测失败会删掉测速历史，
  /// 实时值从有效直接变 0，这是失败结果，不论有没有在途轮次。
  final Map<String, int> _lastLive = {};

  /// 观察连续性中断（分组流清空、节点从分组里消失）：这些节点之前的观察、
  /// 标记和在本轮里的「已确认」都作废。它们回来时的值从头算——内核换了实例或
  /// 清了历史，回来的 0 不能当成「刚测失败」；确实失败过的，缓存里的失败记录
  /// 仍在，线路页照样显示超时。
  void _breakContinuity(Set<String> tags) {
    tags.forEach(_lastLive.remove);
    tags.forEach(_markedAt.remove);
    for (final round in _rounds.values) {
      round.confirmed.removeAll(tags);
    }
    _emit(
      state.copyWith(
        timedOutNodes: state.timedOutNodes.difference(tags),
        unconfirmedNodes: state.unconfirmedNodes.difference(tags),
      ),
    );
  }

  /// 实时值变化之后更新超时 / 未确认标记，并发现不在任何轮次里的失败。
  ///
  /// - 带标记的节点实时值变成**有效**的新值：新结果，撤掉标记；
  /// - 带标记的节点实时值在 0 与超时哨兵之间互变：仍然是失败，标记保留（不能
  ///   因为无效值的写法变了就把超时撤掉，那会让它既不是超时、缓存里也可能没有
  ///   失败记录，线路页只剩「—」）；
  /// - 收尾时被标成历史值的节点，之后才测完且失败（有效 → 无效）：迟到的失败，
  ///   改记超时并写进失败缓存；
  /// - 没有任何标记、也不在任何在途轮次里的节点，实时值从有效变成无效：同样是
  ///   失败（比如自动选择组按间隔做的后台检测，或一轮里测通之后下一次没通），
  ///   记超时并写失败缓存。在途轮次里的节点由收尾统一判定，这里不抢先。
  void _releaseTimeouts(List<OutboundGroup> groups) {
    final live = <String, int>{};
    for (final group in groups) {
      for (final item in group.items) {
        if (item.tag.isEmpty) continue;
        final seen = live[item.tag];
        if (seen == null ||
            (!isMeasurableDelay(seen) && isMeasurableDelay(item.delay))) {
          live[item.tag] = item.delay;
        }
      }
    }
    // 只有「连续观察到」的有效 → 无效才算失败：分组流中途空了（重载、换实例）
    // 之后再出现的节点从头算，不能把「历史被清空」误判成失败。
    final vanished = <String>{
      for (final tag in {..._lastLive.keys, ..._markedAt.keys})
        if (!live.containsKey(tag)) tag,
    };
    if (vanished.isNotEmpty) _breakContinuity(vanished);
    final inRound = <String>{
      for (final round in _rounds.values)
        for (final item
            in _find(groups, round.group)?.items ?? const <OutboundProxy>[])
          item.tag,
    };

    final released = <String>{};
    final lateFailed = <String>{};
    for (final entry in live.entries) {
      final tag = entry.key;
      final delay = entry.value;
      final previous = _lastLive[tag];
      _lastLive[tag] = delay;
      final markedAt = _markedAt[tag];
      if (markedAt == null) {
        if (previous != null &&
            isMeasurableDelay(previous) &&
            !isMeasurableDelay(delay) &&
            !inRound.contains(tag)) {
          lateFailed.add(tag);
        }
        continue;
      }
      if (delay == markedAt) continue;
      if (isMeasurableDelay(delay)) {
        released.add(tag);
      } else if (isMeasurableDelay(markedAt)) {
        // 收尾时被标成历史值的节点，之后才测完、而且失败了：内核删了它的
        // 测速历史，实时值从有效变成 0。这是迟到的失败，不是新结果。
        lateFailed.add(tag);
      } else {
        _markedAt[tag] = delay;
      }
    }
    if (released.isEmpty && lateFailed.isEmpty) return;
    released.forEach(_markedAt.remove);
    for (final tag in lateFailed) {
      _markedAt[tag] = live[tag]!;
    }
    if (lateFailed.isNotEmpty) _recordFailed(lateFailed, _now());
    _emit(
      state.copyWith(
        timedOutNodes: {
          ...state.timedOutNodes.difference(released),
          ...lateFailed,
        },
        unconfirmedNodes: state.unconfirmedNodes
            .difference(released)
            .difference(lateFailed),
      ),
    );
  }

  void _finish(_Round round) => _end(round, markTimeouts: true);

  /// 收尾一轮：取消超时定时器、把**本轮确认的**结果写进缓存、更新状态、
  /// 放行等待者。
  ///
  /// - 确认了且有效：写缓存（刷新测量时间），展示成功，撤掉这个节点身上
  ///   任何超时 / 未确认标记；
  /// - 实时没有有效值（确认失败，或到点一直是 0——内核测失败会删历史，两者
  ///   在分组流里分不开，结果都是没通）：标超时，并把失败写进缓存覆盖旧的
  ///   成功值；
  /// - 没确认但实时值仍有效：不写缓存，保留原值与原测量时间，标为未确认
  ///   （展示历史值）——可能还没测完，也可能恰好同值，无从分辨。
  ///
  /// 内核调用失败时（[markTimeouts] 为假）这一轮可能什么都没测出来，所以只留
  /// **已经观察到**的结果：确认的有效值照常写缓存；确认的失败（本轮出过结果、
  /// 随后实时值无效）记超时并写失败；还没有结果的节点不判，只把缓存里本来就
  /// 有失败记录、实时值仍无效的重新标回超时（不重复写）。不整体恢复开测前的
  /// 标记——那会盖掉别的轮次刚做出的较新判定。
  ///
  /// 超时与未确认两个集合始终互斥。
  void _end(_Round round, {required bool markTimeouts}) {
    if (!identical(_rounds[round.group], round)) return;
    _rounds.remove(round.group);
    round.timeout?.cancel();

    final group = _find(_liveGroups(), round.group);
    final timedOut = <String>{};
    final reasserted = <String>{};
    final unconfirmed = <String>{};
    final measured = <String, int>{};
    if (group != null) {
      final cache = _cache();
      for (final item in _testableItems(group)) {
        final confirmed = round.confirmed.contains(item.tag);
        if (confirmed && isMeasurableDelay(item.delay)) {
          measured[item.tag] = item.delay;
          continue;
        }
        if (!markTimeouts) {
          if (confirmed) {
            timedOut.add(item.tag);
          } else if (!isMeasurableDelay(item.delay) &&
              (cache[item.tag]?.isFailed ?? false)) {
            reasserted.add(item.tag);
          } else {
            continue;
          }
          _markedAt[item.tag] = item.delay;
          continue;
        }
        if (!confirmed && isMeasurableDelay(item.delay)) {
          unconfirmed.add(item.tag);
        } else {
          timedOut.add(item.tag);
        }
        _markedAt[item.tag] = item.delay;
      }
    }
    measured.keys.forEach(_markedAt.remove);
    final at = _now();
    if (measured.isNotEmpty) _recordMeasured(measured, at);
    if (timedOut.isNotEmpty) _recordFailed(timedOut, at);

    final nowTimedOut = {...timedOut, ...reasserted};
    _emit(
      state.copyWith(
        testingGroups: {...state.testingGroups}..remove(round.group),
        pendingNodes: {...state.pendingNodes}..remove(round.group),
        timedOutNodes: {
          ...state.timedOutNodes,
          ...nowTimedOut,
        }.difference(measured.keys.toSet()).difference(unconfirmed),
        unconfirmedNodes: {
          ...state.unconfirmedNodes,
          ...unconfirmed,
        }.difference(measured.keys.toSet()).difference(nowTimedOut),
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
    _markedAt.clear();
    _lastLive.clear();
    _emit(const LatencyTestState());
  }

  void _emit(LatencyTestState next) {
    if (!mounted) return;
    if (next == state) return;
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

OutboundGroup? _find(List<OutboundGroup> groups, String tag) {
  for (final group in groups) {
    if (group.tag == tag) return group;
  }
  return null;
}
