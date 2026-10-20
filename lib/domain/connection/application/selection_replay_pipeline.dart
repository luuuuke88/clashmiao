// 内核实例启动后的手选编排（spec §2「重放手选 → acknowledgeReplay」、§6 出口探测
// 的前置条件）：每个 (profileId, inc, epoch, attempt) 一条、有界的流水线。
//
//   1. 有界等待（[kReplayGroupsWait]）这个实例的第一份实时分组；
//   2. 用运行时真实存在的分组 tag 校验存储里的手选；
//   3. 迁移运行时不存在的分组记录（旧版本按配置文件 tag 记下的 `proxy` 等）到
//      运行时主组——先写目标、确认落盘后才删来源，失败保留来源以便下次重试，
//      重复执行幂等；
//   4. 对每个运行时选择组显式下发：有效手选记录，否则这份运行时配置的默认值
//      （默认值未知则不发）；自动选择（urltest）组不碰；
//   5. 确认重放（`acknowledgeReplay`）；出口探测在确认之后才开始（探测器只认
//      `replayPending == false`）。
//
// 等待超时：不重放任何记录（无法校验），记日志并确认，保证出口探测能开始。
// 绝不对运行时不存在的分组调用 `selectOutbound`。
//
// 归属：每一步 await 之后都核对 (profileId, inc, epoch, attempt) 仍是当前的；
// 不是就整条丢弃——过期任务不确认、不写、不删任何记录。新实例有自己的流水线；
// 实例没变而订阅变了（切到运行时配置相同的订阅不会产生新 attempt）时返回
// [ReplayPipelineOutcome.droppedOwnerChanged]，由调用方按新归属为同一实例重新
// 调度。配置变更暂停期间（备份恢复）激活订阅随时可能再变，归属视为未定：
// 不迁移、不重放、不确认，返回 [ReplayPipelineOutcome.deferred]，由调用方在
// 暂停释放、最终配置意图处理完之后重新评估。

import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 等待这个内核实例第一份实时分组的上限。
const Duration kReplayGroupsWait = Duration(seconds: 5);

/// [kReplayGroupsWait] 的可覆盖入口（测试注入更短 / 更长的等待）。
final replayGroupsWaitProvider = Provider<Duration>((_) => kReplayGroupsWait);

/// 一条流水线的归属。
typedef ReplayOwner = ({
  String? profileId,
  String? profileInc,
  String epoch,
  int attempt,
});

/// 流水线的结局（测试与日志用）。
enum ReplayPipelineOutcome {
  /// 校验、迁移、重放完成并已确认。
  acknowledged,

  /// 等不到这个实例的实时分组：未重放，已确认。
  acknowledgedWithoutGroups,

  /// 内核实例已过期（新 attempt / 已停止）：整条丢弃，未确认。新实例有自己的
  /// 流水线。
  dropped,

  /// 实例仍是当前的，但激活订阅（id 或代际）变了：整条丢弃，未确认。调用方
  /// 必须为这个实例按新归属重新调度——切到运行时配置相同的订阅不会产生新
  /// attempt，没人重新调度的话 `replayPending` 会一直挂着。
  droppedOwnerChanged,

  /// 归属尚未落定（配置变更暂停中：激活订阅随时可能再变）：不迁移、不重放、
  /// 不确认。调用方在暂停释放、最终配置意图处理完之后重新评估。
  deferred,
}

/// 流水线阶段（日志用）。
enum _Stage { awaitGroups, migrate, replay, replayStale, acknowledge }

class SelectionReplayPipeline {
  SelectionReplayPipeline({
    required this._ref,
    required this._port,
    required this._isCurrentInstance,
    bool Function()? ownerUnsettled,
    void Function()? beforeKernelWrite,
    Future<Map<String, String>> Function()? selectorDefaults,
    this._groupsWait = kReplayGroupsWait,
  }) : _ownerUnsettled = ownerUnsettled ?? _never,
       _beforeKernelWrite = beforeKernelWrite ?? _noop,
       _selectorDefaults = selectorDefaults ?? _noDefaults;

  static bool _never() => false;
  static void _noop() {}
  static Future<Map<String, String>> _noDefaults() async => const {};

  /// 这个实例所跑的运行时配置的选择组默认值（选择组 tag → 默认出站）。
  final Future<Map<String, String>> Function() _selectorDefaults;

  /// 每次 `selectOutbound` 之前调用：内核上的选择即将被这条流水线改动，此前
  /// 「已按某归属应用」的记录从这一刻起不再可信（调用方据此作废）。
  final void Function() _beforeKernelWrite;

  final Ref _ref;
  final KernelPort _port;
  final bool Function(String epoch, int attempt) _isCurrentInstance;

  /// 为 true 时归属尚未落定（配置变更暂停中）：任何一步都不往下走，整条以
  /// [ReplayPipelineOutcome.deferred] 结束。
  final bool Function() _ownerUnsettled;
  final Duration _groupsWait;

  /// 这条流水线捕获的归属（[run] 等到订阅就绪之后才有）。确认后它就是「手选
  /// 已按谁应用到这个实例」。
  ReplayOwner? get owner => _owner;
  ReplayOwner? _owner;

  Future<ReplayPipelineOutcome> run(String epoch, int attempt) async {
    // 先等激活订阅与选择存储就绪——内核快照可能先于订阅加载到达，此时存储还是
    // 空的，直接确认等于一次「空重放」。
    try {
      await _ref.read(sharedPreferencesProvider.future);
      await _ref.read(activeProfileProvider.future);
    } catch (e) {
      debugPrint('手选编排：等待订阅就绪失败（按无手选处理）: $e');
    }
    if (!_isCurrentInstance(epoch, attempt)) {
      return ReplayPipelineOutcome.dropped;
    }
    if (_ownerUnsettled()) {
      debugPrint('手选编排 [$epoch/$attempt]：配置变更暂停中，归属未定，延后');
      return ReplayPipelineOutcome.deferred;
    }
    // 激活订阅在第一个 await 之前就切换了也无妨：归属在这里才捕获。

    final profile = _ref.read(activeProfileProvider).valueOrNull;
    final ReplayOwner owner = _owner = (
      profileId: profile?.id,
      profileInc: profile?.inc,
      epoch: epoch,
      attempt: attempt,
    );
    bool owned() => _owns(owner);

    final live = await _awaitLiveGroups(owner);
    if (!owned()) return _drop(owner, _Stage.awaitGroups);
    if (live == null) {
      debugPrint(
        '手选编排 [$epoch/$attempt]：${_groupsWait.inSeconds} s 内没有收到这个实例'
        '的实时分组，无法校验手选，本次不重放',
      );
      await _port.acknowledgeReplay(attempt);
      return ReplayPipelineOutcome.acknowledgedWithoutGroups;
    }

    final runtimeTags = live.tags;
    final groupsByTag = {for (final g in live.groups) g.tag: g};

    if (!await _migrate(owner, runtimeTags, live.groups)) {
      return _drop(owner, _Stage.migrate);
    }

    // 运行时选择组默认值（这份运行时配置的）：订阅里没有手选记录的选择组要
    // 回到它，不能留着上一个订阅的选择。
    final defaults = await _selectorDefaults();
    if (!owned()) return _drop(owner, _Stage.replay);
    final selectorTags = [
      for (final g in live.groups)
        if (g.type == 'selector' && runtimeTags.contains(g.tag)) g.tag,
    ];

    // 重放：对每个运行时选择组都**显式**下发一次——有效的手选记录（节点在该组
    // 里）就发它，否则发这份运行时配置的默认值，默认值未知则不发。不看实时分组
    // 里的「当前选中」：分组快照与我们的写入之间没有先后保证，按它跳过会把迟到
    // 快照当成内核现状（同值下发是幂等的，多发无害）。自动选择（urltest）组永远
    // 不碰。每一项发送前读存储里的最新值；发送后若存储里的值又变了（用户在重放
    // 期间改了选择），继续发最新值直到收敛。stale（内核已换新 attempt）立即放弃
    // 且不确认。
    final sent = <String, String>{};
    for (var pass = 0; pass < 4; pass++) {
      var sentAny = false;
      if (_ownedSelections(owner) == null) {
        return _drop(owner, _Stage.replay);
      }
      for (final group in selectorTags) {
        if (!owned()) return _drop(owner, _Stage.replay);
        final runtimeGroup = groupsByTag[group]!;
        bool member(String? t) =>
            t != null && runtimeGroup.items.any((item) => item.tag == t);
        final stored = _ownedSelections(owner)?[group];
        if (stored != null && !member(stored)) {
          debugPrint('手选编排：[$group] 里没有节点 [$stored]，改发默认值');
        }
        final fallback = defaults[group];
        final String tag;
        if (member(stored)) {
          tag = stored!;
        } else if (member(fallback)) {
          tag = fallback!;
        } else {
          continue; // 没有有效手选、默认值未知：不发
        }
        if (sent[group] == tag) continue;
        sentAny = true;
        sent[group] = tag;
        _beforeKernelWrite();
        final outcome = await _port.selectOutbound(
          group,
          tag,
          expectedAttempt: attempt,
        );
        if (outcome is SelectStale) return _drop(owner, _Stage.replayStale);
        if (outcome is SelectFailed) {
          debugPrint('重放手选代理失败 [$group -> $tag]: ${outcome.code}');
        } else if (tag != stored) {
          debugPrint('手选编排：[$group] 没有有效手选，回到默认值 [$tag]');
        }
      }
      if (!sentAny) break;
    }

    if (!owned()) return _drop(owner, _Stage.acknowledge);
    await _port.acknowledgeReplay(attempt);
    return ReplayPipelineOutcome.acknowledged;
  }

  /// 迁移运行时不存在的分组记录。先写目标并确认落盘，才删来源；目标写入失败
  /// 时撤回内存里的目标、保留来源。返回 false = 归属在途中过期（已停手）。
  Future<bool> _migrate(
    ReplayOwner owner,
    Set<String> runtimeTags,
    List<OutboundGroup> groups,
  ) async {
    final stored = _ownedSelections(owner);
    if (stored == null) return false;
    final plan = planSelectionMigration(
      stored,
      runtimeTags,
      primaryVisibleGroup(groups),
    );
    if (plan.isEmpty) return true;
    if (plan.orphaned.isNotEmpty) {
      debugPrint('手选编排：这些记录对应的分组运行时不存在且无法迁移，保留：${plan.orphaned}');
    }

    // 已确认落盘的目标：计划时就在存储里的运行时分组记录，加上本次写入确认的。
    final confirmed = {
      for (final k in stored.keys)
        if (runtimeTags.contains(k)) k,
    };
    for (final MapEntry(key: source, value: (:target, :node))
        in plan.adopt.entries) {
      final s = _ownedStore(owner);
      if (s == null) return false;
      final previous = _ownedSelections(owner)?[target];
      debugPrint('手选编排：迁移 [$source -> $node] 到运行时分组 [$target]');
      // 记下这次写入的版本：写入失败时只撤销仍属于本次迁移的内存记录——
      // 等待落盘期间用户若又选了别的节点，那是更新的意图，内存与磁盘都不动。
      var version = 0;
      final persisted = await _write(() {
        final w = s.persistTracked(target, node);
        version = w.version;
        return w.persisted;
      });
      if (!_owns(owner)) return false;
      if (!persisted) {
        debugPrint('手选编排：目标 [$target] 写入未落盘，保留来源 [$source] 待下次重试');
        if (s.versionOf(target) == version) {
          await _write(() => s.restore(target, previous, ifVersion: version));
        } else {
          debugPrint('手选编排：[$target] 期间已有更新的选择，不回滚');
        }
        if (!_owns(owner)) return false;
        continue;
      }
      confirmed.add(target);
      if (!await _write(() => s.removeGroups({source}))) {
        debugPrint('手选编排：来源 [$source] 删除未落盘，下次启动再删');
      }
      if (!_owns(owner)) return false;
    }

    for (final MapEntry(key: source, value: target)
        in plan.superseded.entries) {
      if (!confirmed.contains(target)) continue; // 目标没落盘：来源留着
      final s = _ownedStore(owner);
      if (s == null) return false;
      debugPrint('手选编排：[$target] 已有记录，删除运行时不存在的 [$source]');
      await _write(() => s.removeGroups({source}));
      if (!_owns(owner)) return false;
    }
    return true;
  }

  /// 存储写入：异常（例如订阅切换后旧存储已释放）按「未确认落盘」处理。
  Future<bool> _write(Future<bool> Function() op) async {
    try {
      return await op();
    } catch (e) {
      debugPrint('手选编排：存储写入异常（按未落盘处理）: $e');
      return false;
    }
  }

  /// 归属仍有效时返回当前订阅存储里的手选，否则 null。
  Map<String, String>? _ownedSelections(ReplayOwner owner) {
    if (_ownedStore(owner) == null) return null;
    return _ref.read(proxySelectionStoreProvider);
  }

  /// 归属仍有效时返回当前订阅的选择存储，否则 null。
  ProxySelectionStoreNotifier? _ownedStore(ReplayOwner owner) {
    if (!_owns(owner)) return null;
    final store = _ref.read(proxySelectionStoreProvider.notifier);
    if (store.profileId != owner.profileId) return null;
    return store;
  }

  bool _owns(ReplayOwner owner) {
    if (!_isCurrentInstance(owner.epoch, owner.attempt)) return false;
    if (_ownerUnsettled()) return false;
    final profile = _ref.read(activeProfileProvider).valueOrNull;
    return profile?.id == owner.profileId && profile?.inc == owner.profileInc;
  }

  ReplayPipelineOutcome _drop(ReplayOwner owner, _Stage stage) {
    // 只有「实例仍是当前的、且激活订阅确实换了」才算归属变化——调用方据此重新
    // 调度；归属没变却被丢弃（不应发生）按 dropped 处理，避免原地空转。
    final profile = _ref.read(activeProfileProvider).valueOrNull;
    final profileChanged =
        profile?.id != owner.profileId || profile?.inc != owner.profileInc;
    final current =
        stage != _Stage.replayStale &&
        _isCurrentInstance(owner.epoch, owner.attempt);
    final outcome = !current
        ? ReplayPipelineOutcome.dropped
        : _ownerUnsettled()
        ? ReplayPipelineOutcome.deferred
        : profileChanged
        ? ReplayPipelineOutcome.droppedOwnerChanged
        : ReplayPipelineOutcome.dropped;
    debugPrint(
      '手选编排 [${owner.epoch}/${owner.attempt}]：${stage.name} 阶段归属已过期'
      '（${outcome.name}），丢弃（不确认、不写不删）',
    );
    return outcome;
  }

  /// 有界等待 [epoch]/[attempt] 这个实例的第一份实时分组；超时返回 null。
  Future<LiveGroups?> _awaitLiveGroups(ReplayOwner owner) {
    final ReplayOwner(:epoch, :attempt) = owner;
    bool mine(LiveGroups? g) =>
        g != null && g.instance.epoch == epoch && g.instance.attempt == attempt;

    final current = _ref.read(liveGroupsProvider).valueOrNull;
    if (mine(current)) return Future.value(current);

    final done = Completer<LiveGroups?>();
    final sub = _ref.listen<AsyncValue<LiveGroups?>>(liveGroupsProvider, (
      _,
      next,
    ) {
      final g = next.valueOrNull;
      if (mine(g) && !done.isCompleted) done.complete(g);
    });
    // 等待期间激活订阅变了：不必干等到超时，立刻醒来，由调用方按归属丢弃。
    final profileSub = _ref.listen(activeProfileProvider, (_, _) {
      if (!_owns(owner) && !done.isCompleted) done.complete(null);
    });
    final timer = Timer(_groupsWait, () {
      if (!done.isCompleted) done.complete(null);
    });
    return done.future.whenComplete(() {
      timer.cancel();
      sub.close();
      profileSub.close();
    });
  }
}
