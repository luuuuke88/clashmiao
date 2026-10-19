import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';

import '../_fakes/fake_kernel_port.dart';

/// 给 `ConnectionMachine` 的纯函数测试用的驱动器：持有当前状态与「可控时钟」，
/// 记录所有输出动作。时间只在 [advance] / [at] 里前进，从不读系统时钟。
class MachineHarness {
  MachineHarness({DateTime? start})
    : now = start ?? DateTime.utc(2026, 1, 1, 12),
      state = MachineState.initial(start ?? DateTime.utc(2026, 1, 1, 12));

  static const machine = ConnectionMachine();

  MachineState state;
  DateTime now;
  late Transition last;
  bool _any = false;

  /// 所有事件产生的动作，按产生顺序。
  final List<MachineAction> actions = [];

  /// 每个意图 id 收到的终结结果（正确的机器每个 id 恰好一个）。
  final Map<int, List<RequestOutcome>> outcomes = {};

  ConnectionSnapshot get view => last.snapshot;

  Transition feed(MachineEvent e) {
    last = machine.reduce(state, e);
    _any = true;
    state = last.state;
    actions.addAll(last.actions);
    for (final a in last.actions) {
      if (a is SettleRequest) {
        (outcomes[a.id] ??= []).add(a.outcome);
      }
    }
    return last;
  }

  // ── 事件快捷方式 ────────────────────────────────────────────────────

  Transition snap(KernelSnapshot s, {bool fromResync = false}) =>
      feed(SnapshotReceived(s, now: now, fromResync: fromResync));

  Transition link(KernelLink l) => feed(LinkChanged(l, now: now));

  Transition intent(int id, Desired desired, {RequestReason? reason}) => feed(
    UserIntent(
      id: id,
      desired: desired,
      reason:
          reason ??
          (desired == Desired.on
              ? RequestReason.userConnect
              : RequestReason.userDisconnect),
      now: now,
    ),
  );

  Transition prepared(int id, {int revision = 1}) =>
      feed(LaunchPrepared(id: id, launch: launch(revision), now: now));

  Transition prepareFailed(int id, ConnectionFailure f) =>
      feed(LaunchPrepareFailed(id: id, failure: f, now: now));

  Transition receipt(int id, RequestReceipt r) =>
      feed(ReceiptReceived(id: id, receipt: r, now: now));

  Transition sendFailed(int id, ConnectionFailure f) =>
      feed(SendFailed(id: id, failure: f, now: now));

  Transition resyncFailed() => feed(ResyncFailed(now: now));

  /// 推进时钟并投递一个 Tick。
  Transition advance(Duration d) {
    now = now.add(d);
    return feed(Tick(now: now));
  }

  // ── 查询 ─────────────────────────────────────────────────────────

  Iterable<SendRequest> get sends => actions.whereType<SendRequest>();

  Iterable<SideEffect> get effects =>
      actions.whereType<RunEffect>().map((a) => a.effect);

  Iterable<SideEffect> effectsOf(SideEffectKind k) =>
      effects.where((e) => e.kind == k);

  int get resyncs => actions.whereType<Resync>().length;

  /// 本次 [last] 产生的动作。
  List<MachineAction> get lastActions => last.actions;

  bool get hasEvents => _any;

  // ── 构造 ─────────────────────────────────────────────────────────

  static LaunchSpec launch(int revision) => LaunchSpec(
    runtimeConfigPath: 'runtime-config-$revision.json',
    optionsJson: '{}',
    profileName: 'p',
    configRevision: revision,
  );

  static RequestReceipt accepted(int seq, {String epoch = 'e1'}) =>
      RequestReceipt(accepted: true, epoch: epoch, appliedSeq: seq);

  static RequestReceipt rejected(
    RequestRejection why, {
    String epoch = 'e1',
    int appliedSeq = 0,
  }) => RequestReceipt(
    accepted: false,
    reason: why,
    epoch: epoch,
    appliedSeq: appliedSeq,
  );

  static KernelSnapshot snapshot({
    String epoch = 'e1',
    int version = 1,
    KernelStatus status = KernelStatus.stopped,
    int attempt = 0,
    Desired desired = Desired.off,
    DesiredSource source = DesiredSource.system,
    int appliedSeq = 0,
    int? activeConfigRevision,
    KernelFailure? lastFailure,
    bool selectionsReplayNeeded = false,
  }) => FakeKernelPort.snap(
    epoch: epoch,
    version: version,
    status: status,
    attempt: attempt,
    desired: desired,
    source: source,
    appliedSeq: appliedSeq,
    activeConfigRevision: activeConfigRevision,
    lastFailure: lastFailure,
    selectionsReplayNeeded: selectionsReplayNeeded,
  );
}
