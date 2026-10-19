import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';

/// 可编程的 [KernelPort] 测试替身，B3/B4 的状态机与控制器测试复用。
///
/// - [push]：向 [watch] 订阅者推快照，同时更新 [current] 的返回值；
///   [pushLink] 推链路状态。
/// - [requests]：按调用顺序记录所有 [request]；[receiptFor] 决定回执
///   （默认受理并返回 `appliedSeq = seq`）；[requestError] 非空时 request 抛它。
/// - [selectCalls] 记录 [selectOutbound]；[selectResult] 决定结果。
/// - [acknowledged] 记录 [acknowledgeReplay] 的 attempt。
/// - [currentError] 非空时 [current] 抛它；[currentGate] 非空时 [current]
///   等它完成后再返回（用来制造「在途查询」）。
class FakeKernelPort implements KernelPort {
  FakeKernelPort({KernelSnapshot? initial}) : snapshot = initial;

  /// [current] 返回、[watch] 订阅时回放的快照；null 表示尚无快照。
  KernelSnapshot? snapshot;
  KernelLink link = KernelLink.connected;

  final List<DesiredRequest> requests = [];
  final List<({String group, String tag, int? expectedAttempt})> selectCalls =
      [];
  final List<int> acknowledged = [];
  int currentCalls = 0;

  Object? currentError;
  Completer<void>? currentGate;
  Object? requestError;

  /// 自定义回执；默认受理。
  RequestReceipt Function(DesiredRequest r)? receiptFor;

  /// 自定义 select 结果；默认 [SelectOk]。
  SelectOutcome Function(String group, String tag, int? expectedAttempt)?
  selectResult;

  /// 自定义 request 回调（在记录之后、返回回执之前执行），用于让替身像真内核
  /// 一样随请求推进快照。
  FutureOr<void> Function(DesiredRequest r)? onRequest;

  final StreamController<KernelSnapshot> _snapshots =
      StreamController<KernelSnapshot>.broadcast();
  final StreamController<KernelLink> _links =
      StreamController<KernelLink>.broadcast();

  /// 推送一份快照（并成为 [current] 的返回值）。
  void push(KernelSnapshot s) {
    snapshot = s;
    _snapshots.add(s);
  }

  void pushLink(KernelLink l) {
    link = l;
    _links.add(l);
  }

  @override
  Future<KernelSnapshot> current() async {
    currentCalls++;
    final gate = currentGate;
    if (gate != null) await gate.future;
    final err = currentError;
    if (err != null) throw err;
    final s = snapshot;
    if (s == null) {
      throw const KernelPortException('unavailable', 'FakeKernelPort 无快照');
    }
    return s;
  }

  @override
  Stream<KernelSnapshot> watch() async* {
    final s = snapshot;
    if (s != null) yield s;
    yield* _snapshots.stream;
  }

  @override
  Stream<KernelLink> watchLink() async* {
    yield link;
    yield* _links.stream;
  }

  @override
  Future<RequestReceipt> request(DesiredRequest request) async {
    requests.add(request);
    final err = requestError;
    if (err != null) throw err;
    await onRequest?.call(request);
    final custom = receiptFor;
    if (custom != null) return custom(request);
    return RequestReceipt(
      accepted: true,
      epoch: request.epoch,
      appliedSeq: request.seq,
    );
  }

  @override
  Future<void> acknowledgeReplay(int attempt) async {
    acknowledged.add(attempt);
  }

  @override
  Future<SelectOutcome> selectOutbound(
    String groupTag,
    String outboundTag, {
    int? expectedAttempt,
  }) async {
    selectCalls.add((
      group: groupTag,
      tag: outboundTag,
      expectedAttempt: expectedAttempt,
    ));
    return selectResult?.call(groupTag, outboundTag, expectedAttempt) ??
        const SelectOk();
  }

  Future<void> dispose() async {
    await _snapshots.close();
    await _links.close();
  }

  /// 构造快照的便捷工厂，字段默认值是「已停止、空闲」。
  static KernelSnapshot snap({
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
  }) => KernelSnapshot(
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
