import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_hub.dart';

/// 可编程的 [KernelPort] 测试替身，B3/B4 的状态机与控制器测试复用。
///
/// - [push]：向 [watch] 订阅者推快照，同时更新 [current] 的返回值与后续订阅者的
///   首值；订阅时先**原子地**注册并回放首值，首值回调里同步 push/request 不丢事件；
///   [pushLink] 推链路状态。
/// - [requests]：按调用顺序记录所有 [request]；[receiptFor] 决定回执
///   （默认受理并返回 `appliedSeq = seq`）；[requestError] 非空时 request 抛它。
/// - [selectCalls] 记录 [selectOutbound]；[selectResult] 决定结果。
/// - [acknowledged] 记录 [acknowledgeReplay] 的 attempt。
/// - [currentError] 非空时 [current] 抛它；[currentGate] 非空时 [current]
///   等它完成后再返回（用来制造「在途查询」）；[currentResult] 非空时 [current]
///   返回它而不是最近推送的快照。
class FakeKernelPort implements KernelPort {
  FakeKernelPort({KernelSnapshot? initial}) {
    if (initial != null) _snapshots.add(initial);
    _links.add(KernelLink.connected);
  }

  /// [current] 返回、[watch] 订阅时回放的快照；null 表示尚无快照。用 [push] 改。
  KernelSnapshot? get snapshot => _snapshots.latest;

  /// 当前链路状态；用 [pushLink] 改。
  KernelLink get link => _links.latest ?? KernelLink.connected;

  final List<DesiredRequest> requests = [];
  final List<({String group, String tag, int? expectedAttempt})> selectCalls =
      [];
  final List<int> acknowledged = [];
  int currentCalls = 0;

  Object? currentError;
  Completer<void>? currentGate;

  /// 非空时 [current] 返回它（不经事件流）——模拟「重新同步取回的是另一个基线」。
  KernelSnapshot? currentResult;
  Object? requestError;

  /// 自定义回执；默认受理。
  RequestReceipt Function(DesiredRequest r)? receiptFor;

  /// 自定义 select 结果；默认 [SelectOk]。
  SelectOutcome Function(String group, String tag, int? expectedAttempt)?
  selectResult;

  /// 非空时 [selectOutbound] 先等它完成再返回（制造「在途的手选 / 重放」）。
  Completer<void>? onSelectGate;

  /// 自定义 request 回调（在记录之后、返回回执之前执行），用于让替身像真内核
  /// 一样随请求推进快照。
  FutureOr<void> Function(DesiredRequest r)? onRequest;

  // 订阅注册与首值回放在同一同步步骤里完成（KernelPortHub），所以首值回调里
  // 立即 push / pushLink / request 也不会丢事件。
  final KernelPortHub<KernelSnapshot> _snapshots = KernelPortHub();
  final KernelPortHub<KernelLink> _links = KernelPortHub();

  /// 推送一份快照（并成为 [current] 的返回值）。
  void push(KernelSnapshot s) => _snapshots.add(s);

  void pushLink(KernelLink l) => _links.add(l);

  @override
  Future<KernelSnapshot> current() async {
    currentCalls++;
    final gate = currentGate;
    if (gate != null) await gate.future;
    final err = currentError;
    if (err != null) throw err;
    final s = currentResult ?? snapshot;
    if (s == null) {
      throw const KernelPortException('unavailable', 'FakeKernelPort 无快照');
    }
    return s;
  }

  @override
  Stream<KernelSnapshot> watch() => _snapshots.stream();

  @override
  Stream<KernelLink> watchLink() => _links.stream();

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
    final gate = onSelectGate;
    if (gate != null) await gate.future;
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
