// 连接状态机：纯函数，从内核快照与本地请求记录派生界面状态、副作用与请求终结。
//
// 设计见 docs/superpowers/specs/2026-10-19-connection-state-machine-design.md
// §5 与 §10（冲突处以 §10 为准）。
//
// 纯度约束：不读时钟、不做 IO、不依赖 Flutter / Riverpod。时间只来自事件携带的
// `now`；一切跨事件的历史（已执行副作用的 (epoch, attempt) 集合、未终结请求表、
// seq 基线、失联起始时间等）都显式放在 [MachineState] 里，由 [reduce] 返回新状态。
//
// 使用方式（控制器，B4）：持有当前 [MachineState]；每个外部事实（快照、链路变化、
// 用户意图、准备/发送结果、定时器）包成 [MachineEvent] 喂给 [ConnectionMachine.reduce]，
// 然后执行 [Transition.actions]，并按 [Transition.nextWake] 安排一个 [Tick]。

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';

// ─────────────────────────────────────────────────────────────────────────
// 事件
// ─────────────────────────────────────────────────────────────────────────

/// 喂给状态机的外部事实。每个事件都带发生时的时间 [now]。
sealed class MachineEvent {
  const MachineEvent(this.now);

  final DateTime now;
}

/// 收到内核快照（来自 `watch()`，或 `current()` 的重新同步结果）。
///
/// 状态机自己再做一次版本过滤（同纪元内 version 不更大 → 丢弃），作为端口过滤之外
/// 的安全网。[fromResync] 为真时，即使被过滤也表示「这次重新同步已完成」。
final class SnapshotReceived extends MachineEvent {
  const SnapshotReceived(
    this.snapshot, {
    required DateTime now,
    this.fromResync = false,
  }) : super(now);

  final KernelSnapshot snapshot;
  final bool fromResync;
}

/// 一次 [Resync] 动作失败（`current()` 抛错）。
final class ResyncFailed extends MachineEvent {
  const ResyncFailed({required DateTime now}) : super(now);
}

/// 状态流健康度变化（`KernelPort.watchLink`）。
final class LinkChanged extends MachineEvent {
  const LinkChanged(this.link, {required DateTime now}) : super(now);

  final KernelLink link;
}

/// 时间流逝。控制器按 [Transition.nextWake] 安排；多发无害。
final class Tick extends MachineEvent {
  const Tick({required DateTime now}) : super(now);
}

/// 用户（或设置变更）表达了一个新意图。[id] 由调用方分配、全局唯一，用于把
/// [SettleRequest] 对回对应的 `Future<RequestOutcome>`。
///
/// 新意图会立即取代所有「尚未发送」的旧意图（旧意图以 superseded 终结）。
final class UserIntent extends MachineEvent {
  const UserIntent({
    required this.id,
    required this.desired,
    required this.reason,
    required DateTime now,
  }) : super(now);

  final int id;
  final Desired desired;
  final RequestReason reason;
}

/// [PrepareLaunch] 完成：启动产物（配置文件、options、revision）已就绪。
final class LaunchPrepared extends MachineEvent {
  const LaunchPrepared({
    required this.id,
    required this.launch,
    required DateTime now,
  }) : super(now);

  final int id;
  final LaunchSpec launch;
}

/// [PrepareLaunch] 失败（无订阅、配置缺失……）。
final class LaunchPrepareFailed extends MachineEvent {
  const LaunchPrepareFailed({
    required this.id,
    required this.failure,
    required DateTime now,
  }) : super(now);

  final int id;
  final ConnectionFailure failure;
}

/// [SendRequest] 的 `request()` 调用返回了回执。
final class ReceiptReceived extends MachineEvent {
  const ReceiptReceived({
    required this.id,
    required this.receipt,
    required DateTime now,
  }) : super(now);

  final int id;
  final RequestReceipt receipt;
}

/// [SendRequest] 的 `request()` 调用抛错（超时、桥接不可达……）。
final class SendFailed extends MachineEvent {
  const SendFailed({
    required this.id,
    required this.failure,
    required DateTime now,
  }) : super(now);

  final int id;
  final ConnectionFailure failure;
}

// ─────────────────────────────────────────────────────────────────────────
// 动作（输出）
// ─────────────────────────────────────────────────────────────────────────

/// 状态机要求控制器执行的动作，按产生顺序执行。
sealed class MachineAction {
  const MachineAction();
}

/// 为 on 意图准备启动产物；完成后喂回 [LaunchPrepared] / [LaunchPrepareFailed]。
final class PrepareLaunch extends MachineAction {
  const PrepareLaunch(this.id, this.reason);

  final int id;
  final RequestReason reason;
}

/// 调用 `KernelPort.request`；结果喂回 [ReceiptReceived] / [SendFailed]。
final class SendRequest extends MachineAction {
  const SendRequest(this.id, this.request);

  final int id;
  final DesiredRequest request;
}

/// 调用 `KernelPort.current()` 重新同步；结果作为 `SnapshotReceived(fromResync:
/// true)`，失败喂 [ResyncFailed]。
final class Resync extends MachineAction {
  const Resync();
}

/// 执行一个副作用（触觉、评分、重放手选……）。
final class RunEffect extends MachineAction {
  const RunEffect(this.effect);

  final SideEffect effect;
}

/// 请求终结：用 [outcome] 完成意图 [id] 的 `Future<RequestOutcome>`。每个意图
/// 恰好一次。
final class SettleRequest extends MachineAction {
  const SettleRequest(this.id, this.outcome);

  final int id;
  final RequestOutcome outcome;
}

/// 副作用种类（spec §5 副作用表）。
enum SideEffectKind {
  /// 触觉 heavy：用户 connect 请求引发的 started。
  hapticHeavy,

  /// 应用评分请求（与 [hapticHeavy] 同条件）。
  requestReview,

  /// 触觉 medium：用户 disconnect 请求引发的 stopped。
  hapticMedium,

  /// 重放手选，完成后调用 `acknowledgeReplay(attempt)`。
  replaySelections,

  /// 发送 on 请求前置系统代理脏标记（桌面）。
  markSystemProxyDirty,

  /// 用户断开完成后清系统代理脏标记（桌面）。
  clearSystemProxyDirty,

  /// 上报致命失败（控制器检查数据分析开关）。
  reportFailure,
}

/// 一个待执行的副作用。除 [SideEffectKind.markSystemProxyDirty]（描述发送时的快照）
/// 外，[epoch] / [attempt] 即其去重键的一部分。
final class SideEffect {
  const SideEffect(this.kind, {this.epoch, this.attempt, this.failure});

  final SideEffectKind kind;
  final String? epoch;
  final int? attempt;

  /// 仅 [SideEffectKind.reportFailure]。
  final ConnectionFailure? failure;

  @override
  bool operator ==(Object other) =>
      other is SideEffect &&
      other.kind == kind &&
      other.epoch == epoch &&
      other.attempt == attempt &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(kind, epoch, attempt, failure);

  @override
  String toString() => 'SideEffect(${kind.name}, $epoch/$attempt)';
}

/// [ConnectionMachine.reduce] 的输出。
final class Transition {
  const Transition({
    required this.state,
    required this.snapshot,
    required this.actions,
    required this.nextWake,
  });

  /// 新的机器状态（下次 reduce 的输入）。
  final MachineState state;

  /// 对外只读的界面状态。
  final ConnectionSnapshot snapshot;

  /// 待执行动作，按顺序。
  final List<MachineAction> actions;

  /// 最近一个需要「时间流逝」才会触发的截止时间；null 表示无需唤醒。到点后喂
  /// [Tick]。
  final DateTime? nextWake;
}

// ─────────────────────────────────────────────────────────────────────────
// 状态
// ─────────────────────────────────────────────────────────────────────────

/// 本地请求的阶段。
enum RequestStage {
  /// 等待启动产物（仅 on）。
  preparing,

  /// 已就绪，等待快照提供纪元与 seq 基线，或等待重发时机。
  ready,

  /// `request()` 已发出，回执未回。
  inFlight,

  /// 回执已被受理，等待快照确认与完成。
  awaiting,
}

/// 一个尚未终结的本地意图/请求。
final class RequestRecord {
  const RequestRecord({
    required this.id,
    required this.desired,
    required this.reason,
    required this.stage,
    this.launch,
    this.seq,
    this.sentAt,
    this.receiptAt,
    this.resends = 0,
    this.failureKeyAtSend,
  });

  final int id;
  final Desired desired;
  final RequestReason reason;
  final RequestStage stage;

  /// on 意图在准备完成后才有。
  final LaunchSpec? launch;

  /// 发送时分配（§10.1）；尚未发送为 null。
  final int? seq;
  final DateTime? sentAt;
  final DateTime? receiptAt;

  /// 因 stale / wrongEpoch 回执重发的次数。
  final int resends;

  /// 发送时已见过的内核失败的键；用来区分「发送之后才出现的失败」（归属判定用）。
  final String? failureKeyAtSend;

  /// 「内核有没有确认」的时间基准：回执到达时刻，没有则发送时刻。
  DateTime? get ackBase => receiptAt ?? sentAt;

  RequestRecord copyWith({
    RequestStage? stage,
    LaunchSpec? launch,
    int? seq,
    bool clearSeq = false,
    DateTime? sentAt,
    DateTime? receiptAt,
    bool clearTimes = false,
    int? resends,
    String? failureKeyAtSend,
  }) {
    return RequestRecord(
      id: id,
      desired: desired,
      reason: reason,
      stage: stage ?? this.stage,
      launch: launch ?? this.launch,
      seq: clearSeq ? null : (seq ?? this.seq),
      sentAt: clearTimes ? null : (sentAt ?? this.sentAt),
      receiptAt: clearTimes ? null : (receiptAt ?? this.receiptAt),
      resends: resends ?? this.resends,
      failureKeyAtSend: failureKeyAtSend ?? this.failureKeyAtSend,
    );
  }

  @override
  String toString() =>
      'RequestRecord(#$id ${desired.name} ${stage.name} seq=$seq)';
}

/// 副作用去重键：同一 (epoch, attempt, kind) 至多执行一次。
typedef EffectKey = (String epoch, int attempt, SideEffectKind kind);

/// 状态机的全部跨事件状态。对外只读；只有 [ConnectionMachine] 能产生新值。
final class MachineState {
  /// 初始状态。[now] 是机器创建的时间，用于「始终没有首个快照」的 10 s 判定。
  MachineState.initial(DateTime now)
    : _waitSince = now,
      _link = KernelLink.connected,
      _requests = const [],
      _reasonBySeq = const {},
      _done = const {};

  MachineState._copy(MachineState o)
    : _waitSince = o._waitSince,
      _snapshot = o._snapshot,
      _link = o._link,
      _lostSince = o._lostSince,
      _nextSeq = o._nextSeq,
      _awaitEpoch = o._awaitEpoch,
      _requests = List.of(o._requests),
      _reasonBySeq = Map.of(o._reasonBySeq),
      _done = Set.of(o._done),
      _startedAt = o._startedAt,
      _attached = o._attached,
      _unresponsiveLost = o._unresponsiveLost,
      _unresponsiveSeq = o._unresponsiveSeq,
      _unresponsiveCount = o._unresponsiveCount,
      _localFailure = o._localFailure,
      _localFailureCount = o._localFailureCount,
      _failureSeq = o._failureSeq,
      _lastFailureKey = o._lastFailureKey,
      _seedFailureKey = o._seedFailureKey,
      _seenKernelFailureKey = o._seenKernelFailureKey,
      _resyncSince = o._resyncSince;

  // 以下字段只在 ConnectionMachine.reduce 里、对刚复制出来的新状态修改；
  // 对外一律只读。
  DateTime _waitSince;
  KernelSnapshot? _snapshot;
  KernelLink _link;
  DateTime? _lostSince;
  int? _nextSeq;
  String? _awaitEpoch;
  final List<RequestRecord> _requests;
  Map<int, RequestReason> _reasonBySeq;
  Set<EffectKey> _done;
  DateTime? _startedAt;
  bool _attached = false;
  bool _unresponsiveLost = false;
  int? _unresponsiveSeq;
  int _unresponsiveCount = 0;
  ConnectionFailure? _localFailure;
  int _localFailureCount = 0;
  int _failureSeq = 0;
  String? _lastFailureKey;
  bool _seedFailureKey = false;
  String? _seenKernelFailureKey;
  DateTime? _resyncSince;

  /// 最近一个被接受的内核快照；尚无为 null。
  KernelSnapshot? get snapshot => _snapshot;

  /// 状态流健康度。
  KernelLink get link => _link;

  /// 下一个要分配的请求序号（首个快照的 `appliedSeq + 1` 为基线，每个纪元重设）。
  int? get nextSeq => _nextSeq;

  /// 尚未终结的本地请求，按创建顺序；最后一个是「最新意图」。
  List<RequestRecord> get requests => List.unmodifiable(_requests);

  /// 本纪元内本进程已发出的请求原因（seq → reason）。
  Map<int, RequestReason> get reasonBySeq => Map.unmodifiable(_reasonBySeq);

  /// 本纪元内已执行的副作用 (epoch, attempt, kind) 集合。
  Set<EffectKey> get executedEffects => Set.unmodifiable(_done);

  /// 本次连接建立的时间（attached / 未连接为 null）。
  DateTime? get startedAt => _startedAt;

  /// 首个快照即为 started（冷启动挂上运行中隧道），时长未知。
  bool get attached => _attached;

  /// 状态流失联（或始终无快照）已超过 10 s，或请求长时间得不到确认。
  bool get nativeUnresponsive => _unresponsiveLost || _unresponsiveSeq != null;

  /// 失联起始时间；未失联为 null。
  DateTime? get lostSince => _lostSince;

  /// 已递增到的 failureSeq。
  int get failureSeq => _failureSeq;

  /// 最新的未终结意图（含尚未发送的）。
  RequestRecord? get latestRequest => _requests.isEmpty ? null : _requests.last;

  /// 失联判定的起点：已报 lost 则为 lost 的时刻；从未有快照则为等待起点。
  DateTime? get _silentSince =>
      _lostSince ?? (_snapshot == null ? _waitSince : null);

  // ── 变更助手（仅 reduce 内部使用）──────────────────────────────

  int _indexOf(int id) => _requests.indexWhere((r) => r.id == id);

  RequestRecord? _find(int id) {
    final i = _indexOf(id);
    return i < 0 ? null : _requests[i];
  }

  void _replace(RequestRecord r) {
    _requests[_indexOf(r.id)] = r;
  }

  void _remove(int id) {
    _requests.removeWhere((r) => r.id == id);
  }

  bool get _hasUnresponsive => nativeUnresponsive;
}

// ─────────────────────────────────────────────────────────────────────────
// 状态机
// ─────────────────────────────────────────────────────────────────────────

/// 纯函数连接状态机。无字段、不读时钟、不做 IO。
class ConnectionMachine {
  const ConnectionMachine();

  /// `(状态, 事件) → (新状态, 界面快照, 动作, 下次唤醒)`。
  Transition reduce(MachineState s, MachineEvent e) {
    final w = MachineState._copy(s);
    final actions = <MachineAction>[];
    switch (e) {
      case SnapshotReceived():
        _onSnapshot(w, e, actions);
      case ResyncFailed():
        _resyncDone(w, e.now, actions);
      case LinkChanged():
        _onLink(w, e);
      case Tick():
        break;
      case UserIntent():
        _onIntent(w, e, actions);
      case LaunchPrepared():
        _onPrepared(w, e);
      case LaunchPrepareFailed():
        _onPrepareFailed(w, e, actions);
      case ReceiptReceived():
        _onReceipt(w, e, actions);
      case SendFailed():
        _onSendFailed(w, e, actions);
    }
    _checkDeadlines(w, e.now, actions);
    _pumpSend(w, e.now, actions);
    final view = _finalize(w);
    return Transition(
      state: w,
      snapshot: view,
      actions: List.unmodifiable(actions),
      nextWake: _nextWake(w),
    );
  }

  // ── 内核快照 ────────────────────────────────────────────────────

  void _onSnapshot(
    MachineState w,
    SnapshotReceived e,
    List<MachineAction> actions,
  ) {
    final snap = e.snapshot;
    final prev = w._snapshot;
    final epochChanged = prev == null || prev.epoch != snap.epoch;
    if (!epochChanged && snap.version <= prev.version) {
      // 乱序/重复：丢弃。但这仍可能是一次重新同步的完成。
      if (e.fromResync) _resyncDone(w, e.now, actions);
      return;
    }

    if (epochChanged) {
      _resetEpoch(w, snap, actions);
    } else if (w._nextSeq! <= snap.appliedSeq) {
      w._nextSeq = snap.appliedSeq + 1;
    }
    final prevStatus = epochChanged ? null : prev.status;
    w._snapshot = snap;
    if (w._awaitEpoch == snap.epoch) w._awaitEpoch = null;

    // 收到快照且链路正常 = 原生可达。
    if (w._link == KernelLink.connected) w._unresponsiveLost = false;
    final blocked = w._unresponsiveSeq;
    if (blocked != null && snap.appliedSeq >= blocked) {
      w._unresponsiveSeq = null;
    }

    _runSnapshotEffects(w, snap, prevStatus, epochChanged, e.now, actions);
    _resolveRequests(w, snap, actions);
    if (e.fromResync) _resyncDone(w, e.now, actions);
  }

  /// 纪元变化（含首个快照）：重置所有纪元内基线；已发送未终结的请求被中断。
  void _resetEpoch(
    MachineState w,
    KernelSnapshot snap,
    List<MachineAction> actions,
  ) {
    for (final r in List.of(w._requests)) {
      if (r.stage == RequestStage.inFlight ||
          r.stage == RequestStage.awaiting) {
        w._remove(r.id);
        actions.add(SettleRequest(r.id, const RequestInterrupted()));
      }
    }
    w._done = {};
    w._reasonBySeq = {};
    w._startedAt = null;
    w._attached = false;
    w._nextSeq = snap.appliedSeq + 1;
    w._awaitEpoch = null;
    w._localFailure = null;
    w._unresponsiveSeq = null;
    w._resyncSince = null;
    w._seedFailureKey = true;
    w._seenKernelFailureKey = _kernelFailureKey(snap);
  }

  void _runSnapshotEffects(
    MachineState w,
    KernelSnapshot snap,
    KernelStatus? prevStatus,
    bool first,
    DateTime now,
    List<MachineAction> actions,
  ) {
    void once(SideEffectKind kind, {ConnectionFailure? failure}) {
      final key = (snap.epoch, snap.attempt, kind);
      if (!w._done.add(key)) return;
      actions.add(
        RunEffect(
          SideEffect(
            kind,
            epoch: snap.epoch,
            attempt: snap.attempt,
            failure: failure,
          ),
        ),
      );
    }

    final reason = w._reasonBySeq[snap.appliedSeq];

    if (snap.status == KernelStatus.started) {
      if (first) {
        // 冷启动挂上运行中隧道：时长未知，不触觉、不评分。
        w._attached = true;
        w._startedAt = null;
      } else if (w._startedAt == null &&
          !w._attached &&
          snap.desired == Desired.on) {
        // 一次新建立的连接（重载不会走到这里：startedAt 已有值）。
        w._startedAt = now;
        if (snap.source == DesiredSource.app &&
            reason == RequestReason.userConnect) {
          once(SideEffectKind.hapticHeavy);
          once(SideEffectKind.requestReview);
        }
      }
    }

    if (snap.status == KernelStatus.stopped && snap.desired == Desired.off) {
      if (prevStatus != null &&
          prevStatus != KernelStatus.stopped &&
          snap.source == DesiredSource.app &&
          reason == RequestReason.userDisconnect) {
        once(SideEffectKind.hapticMedium);
        once(SideEffectKind.clearSystemProxyDirty);
      }
      w._startedAt = null;
      w._attached = false;
    }

    if (snap.status == KernelStatus.started && snap.selectionsReplayNeeded) {
      once(SideEffectKind.replaySelections);
    }

    // 新的 lastFailure：致命类上报（冷启动时已存在的旧失败只播种，不上报）。
    final fkey = _kernelFailureKey(snap);
    if (fkey != null && fkey != w._seenKernelFailureKey) {
      w._seenKernelFailureKey = fkey;
      final mapped = ConnectionFailure.fromKernel(snap.lastFailure!);
      if (mapped.isFatal) {
        actions.add(
          RunEffect(
            SideEffect(
              SideEffectKind.reportFailure,
              epoch: snap.epoch,
              attempt: snap.attempt,
              failure: mapped,
            ),
          ),
        );
      }
    }
  }

  static String? _kernelFailureKey(KernelSnapshot snap) {
    final f = snap.lastFailure;
    if (f == null) return null;
    return 'k|${snap.epoch}|${f.code.name}|${f.attempt}|${f.seq}';
  }

  // ── 请求终结（spec §10.6）────────────────────────────────────────

  void _resolveRequests(
    MachineState w,
    KernelSnapshot snap,
    List<MachineAction> actions,
  ) {
    for (final r in List.of(w._requests)) {
      final outcome = _evaluate(r, snap);
      if (outcome == null) continue;
      w._remove(r.id);
      actions.add(SettleRequest(r.id, outcome));
    }
  }

  RequestOutcome? _evaluate(RequestRecord r, KernelSnapshot snap) {
    final seq = r.seq;
    if (seq == null || snap.appliedSeq < seq) return null;
    final lf = snap.lastFailure;
    if (lf != null) {
      final attributed =
          lf.seq == seq ||
          (lf.seq == null &&
              r.desired == Desired.on &&
              snap.appliedSeq == seq &&
              snap.desired == Desired.off &&
              lf.attempt == snap.attempt &&
              _kernelFailureKey(snap) != r.failureKeyAtSend);
      if (attributed) {
        return RequestFailed(ConnectionFailure.fromKernel(lf));
      }
    }
    if (snap.appliedSeq > seq) return const RequestSuperseded();
    switch (r.desired) {
      case Desired.on:
        // 被受理之后期望又变成了 off：外部入口（磁贴/系统撤销）覆盖了它。
        if (snap.desired == Desired.off) return const RequestSuperseded();
        if (snap.status == KernelStatus.started &&
            snap.activeConfigRevision == r.launch?.configRevision) {
          return const RequestSucceeded();
        }
        return null;
      case Desired.off:
        if (snap.desired == Desired.on) return const RequestSuperseded();
        if (snap.status == KernelStatus.stopped) {
          return const RequestSucceeded();
        }
        return null;
    }
  }

  // ── 链路 ────────────────────────────────────────────────────────

  void _onLink(MachineState w, LinkChanged e) {
    switch (e.link) {
      case KernelLink.lost:
        if (w._link != KernelLink.lost) {
          w._link = KernelLink.lost;
          w._lostSince = e.now;
        }
      case KernelLink.connected:
        // 从失联恢复：原生可达，之前因失联/迟迟不确认而判的无响应一并撤销。
        if (w._link == KernelLink.lost) w._unresponsiveSeq = null;
        w._link = KernelLink.connected;
        w._lostSince = null;
        w._unresponsiveLost = false;
    }
  }

  // ── 用户意图 ────────────────────────────────────────────────────

  void _onIntent(MachineState w, UserIntent e, List<MachineAction> actions) {
    if (w._find(e.id) != null) return; // id 重复：忽略
    // 取代所有尚未发送的旧意图（只可能是最新的那个）。
    final last = w.latestRequest;
    if (last != null &&
        (last.stage == RequestStage.preparing ||
            last.stage == RequestStage.ready)) {
      w._remove(last.id);
      actions.add(SettleRequest(last.id, const RequestSuperseded()));
    }
    w._localFailure = null;
    if (w._hasUnresponsive) {
      // 点击 = 立即重新同步后重发最新意图；失联宽限重新计时。
      w._unresponsiveLost = false;
      w._unresponsiveSeq = null;
      if (w._lostSince != null) w._lostSince = e.now;
      w._waitSince = e.now;
      if (w._resyncSince == null) {
        w._resyncSince = e.now;
        actions.add(const Resync());
      }
    }
    final needsPrepare = e.desired == Desired.on;
    w._requests.add(
      RequestRecord(
        id: e.id,
        desired: e.desired,
        reason: e.reason,
        stage: needsPrepare ? RequestStage.preparing : RequestStage.ready,
      ),
    );
    if (needsPrepare) actions.add(PrepareLaunch(e.id, e.reason));
  }

  void _onPrepared(MachineState w, LaunchPrepared e) {
    final r = w._find(e.id);
    if (r == null || r.stage != RequestStage.preparing) return;
    w._replace(r.copyWith(stage: RequestStage.ready, launch: e.launch));
  }

  void _onPrepareFailed(
    MachineState w,
    LaunchPrepareFailed e,
    List<MachineAction> actions,
  ) {
    final r = w._find(e.id);
    if (r == null || r.stage != RequestStage.preparing) return;
    w._remove(r.id);
    w._localFailure = e.failure;
    w._localFailureCount++;
    actions.add(SettleRequest(r.id, RequestFailed(e.failure)));
  }

  // ── 发送与回执（spec §10.1）─────────────────────────────────────

  /// 把「就绪」的最新意图发出去。seq 在此刻才分配：准备期间被取代的意图从不占号。
  void _pumpSend(MachineState w, DateTime now, List<MachineAction> actions) {
    final r = w.latestRequest;
    final snap = w._snapshot;
    if (r == null || r.stage != RequestStage.ready || snap == null) return;
    final awaiting = w._awaitEpoch;
    if (awaiting != null && snap.epoch != awaiting) return;
    final seq = w._nextSeq ?? (snap.appliedSeq + 1);
    w._nextSeq = seq + 1;
    w._reasonBySeq[seq] = r.reason;
    _pruneReasons(w);
    w._replace(
      r.copyWith(
        stage: RequestStage.inFlight,
        seq: seq,
        sentAt: now,
        failureKeyAtSend: w._seenKernelFailureKey,
      ),
    );
    if (r.desired == Desired.on) {
      actions.add(
        RunEffect(
          SideEffect(
            SideEffectKind.markSystemProxyDirty,
            epoch: snap.epoch,
            attempt: snap.attempt,
          ),
        ),
      );
    }
    actions.add(
      SendRequest(
        r.id,
        DesiredRequest(
          epoch: snap.epoch,
          seq: seq,
          desired: r.desired,
          reason: r.reason,
          launch: r.desired == Desired.on ? r.launch : null,
        ),
      ),
    );
  }

  static void _pruneReasons(MachineState w) {
    const keep = 32;
    if (w._reasonBySeq.length <= keep) return;
    final seqs = w._reasonBySeq.keys.toList()..sort();
    for (final k in seqs.take(seqs.length - keep)) {
      w._reasonBySeq.remove(k);
    }
  }

  void _onReceipt(
    MachineState w,
    ReceiptReceived e,
    List<MachineAction> actions,
  ) {
    final rc = e.receipt;
    // 回执带来的 appliedSeq 永远是有效的基线信息（即便意图已终结）。
    final next = w._nextSeq;
    if (next != null &&
        next <= rc.appliedSeq &&
        w._snapshot?.epoch == rc.epoch) {
      w._nextSeq = rc.appliedSeq + 1;
    }
    final r = w._find(e.id);
    if (r == null) return;
    if (r.stage != RequestStage.inFlight && r.stage != RequestStage.awaiting) {
      return;
    }
    if (rc.accepted) {
      if (r.stage == RequestStage.inFlight) {
        w._replace(r.copyWith(stage: RequestStage.awaiting, receiptAt: e.now));
      }
      return;
    }
    final rejection = rc.reason ?? RequestRejection.stale;
    if (w.latestRequest?.id != r.id) {
      // 更新的意图已经存在：旧请求被拒绝只说明它被取代了。
      w._remove(r.id);
      actions.add(SettleRequest(r.id, const RequestSuperseded()));
      return;
    }
    if (r.resends >= ConnectionTiming.maxResends) {
      final failure = PlatformFailure(rejection.name, '请求被内核反复拒绝');
      w._remove(r.id);
      w._localFailure = failure;
      w._localFailureCount++;
      actions.add(SettleRequest(r.id, RequestFailed(failure)));
      return;
    }
    // 回到「就绪」，由 _pumpSend 用新基线重发。
    w._replace(
      r.copyWith(
        stage: RequestStage.ready,
        clearSeq: true,
        clearTimes: true,
        resends: r.resends + 1,
      ),
    );
    if (rejection == RequestRejection.wrongEpoch &&
        w._snapshot?.epoch != rc.epoch) {
      // 原生纪元已变而我们还不知道：先重新同步，新纪元快照到达后才重发。
      w._awaitEpoch = rc.epoch;
      w._resyncSince ??= e.now;
      actions.add(const Resync());
    }
  }

  void _onSendFailed(
    MachineState w,
    SendFailed e,
    List<MachineAction> actions,
  ) {
    final r = w._find(e.id);
    if (r == null) return;
    if (r.stage != RequestStage.inFlight && r.stage != RequestStage.awaiting) {
      return;
    }
    final isLatest = w.latestRequest?.id == r.id;
    w._remove(r.id);
    if (!isLatest) {
      actions.add(SettleRequest(r.id, const RequestSuperseded()));
      return;
    }
    w._localFailure = e.failure;
    w._localFailureCount++;
    actions.add(SettleRequest(r.id, RequestFailed(e.failure)));
  }

  // ── 截止时间：未确认请求（§5）与失联（§10.8）──────────────────────

  Iterable<RequestRecord> _unconfirmed(MachineState w) {
    final applied = w._snapshot?.appliedSeq;
    if (applied == null) return const [];
    return w._requests.where(
      (r) =>
          (r.stage == RequestStage.inFlight ||
              r.stage == RequestStage.awaiting) &&
          r.seq != null &&
          r.seq! > applied,
    );
  }

  void _checkDeadlines(
    MachineState w,
    DateTime now,
    List<MachineAction> actions,
  ) {
    // 失联 / 始终没有首个快照。
    final silent = w._silentSince;
    if (silent != null &&
        !w._unresponsiveLost &&
        now.difference(silent) >= ConnectionTiming.nativeLostTimeout) {
      w._unresponsiveLost = true;
      w._unresponsiveCount++;
      for (final r in List.of(w._requests)) {
        w._remove(r.id);
        actions.add(
          SettleRequest(r.id, const RequestFailed(NativeUnresponsive())),
        );
      }
      w._resyncSince = null;
    }

    // 未确认请求：先重新同步，仍追不上才判无响应。
    final since = w._resyncSince;
    if (since == null) {
      final overdue = _unconfirmed(w).any(
        (r) =>
            r.ackBase != null &&
            now.difference(r.ackBase!) >=
                ConnectionTiming.unconfirmedRequestTimeout,
      );
      if (overdue) {
        w._resyncSince = now;
        actions.add(const Resync());
      }
    } else if (now.difference(since) >= ConnectionTiming.resyncGrace) {
      _resyncDone(w, now, actions);
    }
  }

  /// 一次重新同步结束（成功、失败或宽限到期）：仍追不上、且已过 5 s 的请求判失败。
  void _resyncDone(MachineState w, DateTime now, List<MachineAction> actions) {
    w._resyncSince = null;
    int? maxSeq;
    for (final r in List.of(_unconfirmed(w))) {
      final base = r.ackBase;
      if (base == null ||
          now.difference(base) < ConnectionTiming.unconfirmedRequestTimeout) {
        continue;
      }
      w._remove(r.id);
      actions.add(
        SettleRequest(r.id, const RequestFailed(NativeUnresponsive())),
      );
      if (maxSeq == null || r.seq! > maxSeq) maxSeq = r.seq;
    }
    if (maxSeq != null) {
      w._unresponsiveSeq = maxSeq;
      w._unresponsiveCount++;
    }
  }

  DateTime? _nextWake(MachineState w) {
    DateTime? best;
    void consider(DateTime t) {
      if (best == null || t.isBefore(best!)) best = t;
    }

    final silent = w._silentSince;
    if (silent != null && !w._unresponsiveLost) {
      consider(silent.add(ConnectionTiming.nativeLostTimeout));
    }
    final since = w._resyncSince;
    if (since != null) {
      consider(since.add(ConnectionTiming.resyncGrace));
    } else {
      for (final r in _unconfirmed(w)) {
        final base = r.ackBase;
        if (base != null) {
          consider(base.add(ConnectionTiming.unconfirmedRequestTimeout));
        }
      }
    }
    return best;
  }

  // ── 派生界面状态（spec §5 phase 表）───────────────────────────────

  ConnectionSnapshot _finalize(MachineState w) {
    final snap = w._snapshot;
    final (phase, failure, key) = _derive(w);

    // failureSeq：展示出一个没见过的失败就 +1；冷启动首个快照里的旧失败只播种。
    if (key != null && key != w._lastFailureKey) {
      if (!w._seedFailureKey) w._failureSeq++;
      w._lastFailureKey = key;
    }
    if (snap != null) w._seedFailureKey = false;

    final pending = _pending(w);
    return ConnectionSnapshot(
      phase: phase,
      failure: failure,
      failureSeq: w._failureSeq,
      startedAt: w._startedAt,
      origin: snap == null
          ? null
          : (pending != null ? DesiredSource.app : snap.source),
      stale: snap != null && w._link == KernelLink.lost,
      epoch: snap?.epoch,
      attempt: snap?.attempt,
      replayPending: snap != null && snap.selectionsReplayNeeded,
    );
  }

  /// 最新的「尚未被内核确认」的本地请求（未发送，或 seq 超过快照的 appliedSeq）。
  RequestRecord? _pending(MachineState w) {
    final snap = w._snapshot;
    if (snap == null) return null;
    for (final r in w._requests.reversed) {
      final seq = r.seq;
      if (seq == null || seq > snap.appliedSeq) return r;
    }
    return null;
  }

  (ConnectionPhase, ConnectionFailure?, String?) _derive(MachineState w) {
    final snap = w._snapshot;

    // 失败的优先级：失联 > 本地失败（准备/RPC/反复拒绝）> 内核 lastFailure。
    ConnectionFailure? localOrNative;
    String? localKey;
    if (w._hasUnresponsive) {
      localOrNative = const NativeUnresponsive();
      localKey = 'n|${w._unresponsiveCount}';
    } else if (w._localFailure != null) {
      localOrNative = w._localFailure;
      localKey = 'l|${w._localFailureCount}';
    }

    if (snap == null) {
      return (ConnectionPhase.resolving, localOrNative, localKey);
    }

    final pending = _pending(w);
    if (pending != null) {
      // 有未确认的本地请求：按它的方向显示，且不展示失败。
      if (pending.desired == Desired.off) {
        return (ConnectionPhase.disconnecting, null, null);
      }
      final established = w._startedAt != null || w._attached;
      if (snap.desired == Desired.on &&
          (snap.status == KernelStatus.started || established)) {
        final sameRevision =
            snap.status == KernelStatus.started &&
            pending.launch != null &&
            pending.launch!.configRevision == snap.activeConfigRevision;
        return (
          sameRevision
              ? ConnectionPhase.connected
              : ConnectionPhase.reconnecting,
          null,
          null,
        );
      }
      return (ConnectionPhase.connecting, null, null);
    }

    final ConnectionPhase phase;
    if (snap.desired == Desired.on) {
      if (snap.status == KernelStatus.started) {
        // 已被受理但运行实例还不是它：配置待生效。
        final waiting = w._requests.any(
          (r) =>
              r.desired == Desired.on &&
              r.launch != null &&
              r.launch!.configRevision != snap.activeConfigRevision,
        );
        phase = waiting
            ? ConnectionPhase.reconnecting
            : ConnectionPhase.connected;
      } else {
        final established = w._startedAt != null || w._attached;
        phase = established
            ? ConnectionPhase.reconnecting
            : ConnectionPhase.connecting;
      }
    } else {
      phase = snap.status == KernelStatus.stopped
          ? ConnectionPhase.disconnected
          : ConnectionPhase.disconnecting;
    }

    if (localOrNative != null) return (phase, localOrNative, localKey);

    // 内核 lastFailure 的归属（spec §5）。
    final lf = snap.lastFailure;
    if (lf != null) {
      final mine = lf.seq == snap.appliedSeq || lf.attempt == snap.attempt;
      final show = switch (phase) {
        ConnectionPhase.disconnected => mine,
        ConnectionPhase.disconnecting =>
          mine && lf.code == KernelFailureCode.kernelUnresponsive,
        _ => false,
      };
      if (show) {
        return (
          phase,
          ConnectionFailure.fromKernel(lf),
          _kernelFailureKey(snap),
        );
      }
    }
    return (phase, null, null);
  }
}
