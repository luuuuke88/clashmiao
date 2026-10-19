import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/machine_harness.dart';

// 「每个请求最终都有终结结果」（计划 P3）：脚本化的假世界 + 可控时钟。
// 世界按脚本执行机器给出的动作（准备、发送、重新同步），时间只通过
// nextWake → Tick 推进。

class _World {
  _World(this.h);

  final MachineHarness h;

  /// 准备结果：null = 成功；否则失败。
  ConnectionFailure? prepareFailure;

  /// request() 的结果：null = 受理；否则抛错。
  ConnectionFailure? sendFailure;

  /// request() 回执（sendFailure 为 null 时使用）。
  RequestReceipt Function(SendRequest s)? receipt;

  /// 重新同步的结果；null = current() 失败。
  KernelSnapshot? Function()? resyncResult;

  /// 重新同步的调用一直不返回（既无快照也无失败）。
  bool resyncHangs = false;

  int _cursor = 0;

  void pump() {
    while (_cursor < h.actions.length) {
      final a = h.actions[_cursor++];
      switch (a) {
        case PrepareLaunch():
          final f = prepareFailure;
          if (f != null) {
            h.prepareFailed(a.id, f);
          } else {
            h.prepared(a.id, revision: 1);
          }
        case SendRequest():
          final f = sendFailure;
          if (f != null) {
            h.sendFailed(a.id, f);
          } else {
            h.receipt(
              a.id,
              receipt?.call(a) ??
                  MachineHarness.accepted(
                    a.request.seq,
                    epoch: a.request.epoch,
                  ),
            );
          }
        case Resync():
          if (resyncHangs) break;
          final s = resyncResult?.call();
          if (s == null) {
            h.resyncFailed();
          } else {
            h.snap(s, fromResync: true);
          }
        case RunEffect() || SettleRequest():
          break;
      }
    }
  }

  /// 推进可控时钟到 [d] 之后，逐个兑现 nextWake。
  void run(Duration d) {
    final end = h.now.add(d);
    pump();
    for (var guard = 0; guard < 1000; guard++) {
      final wake = h.last.nextWake;
      if (wake == null || wake.isAfter(end)) break;
      h.now = wake;
      h.feed(Tick(now: wake));
      pump();
    }
    h.now = end;
    h.feed(Tick(now: end));
    pump();
  }
}

KernelSnapshot _s({
  String epoch = 'e1',
  int version = 1,
  KernelStatus status = KernelStatus.stopped,
  int attempt = 0,
  Desired desired = Desired.off,
  DesiredSource source = DesiredSource.app,
  int appliedSeq = 0,
  int? rev,
  KernelFailure? failure,
}) => MachineHarness.snapshot(
  epoch: epoch,
  version: version,
  status: status,
  attempt: attempt,
  desired: desired,
  source: source,
  appliedSeq: appliedSeq,
  activeConfigRevision: rev,
  lastFailure: failure,
);

void _expectOneOutcomeEach(MachineHarness h, Iterable<int> ids) {
  for (final id in ids) {
    expect(h.outcomes[id], hasLength(1), reason: '意图 #$id 必须恰好终结一次');
  }
  expect(h.state.requests, isEmpty, reason: '请求表必须清空');
}

void main() {
  test('内核正常响应：connect 与 disconnect 各自 succeeded', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h);
    h.intent(1, Desired.on);
    w.pump();
    h.snap(
      _s(
        version: 2,
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        appliedSeq: 1,
        rev: 1,
      ),
    );
    h.intent(2, Desired.off);
    w.pump();
    h.snap(_s(version: 3, attempt: 1, appliedSeq: 2));
    w.run(const Duration(seconds: 60));
    expect(h.outcomes[1], [const RequestSucceeded()]);
    expect(h.outcomes[2], [const RequestSucceeded()]);
    _expectOneOutcomeEach(h, [1, 2]);
    expect(h.view.phase, ConnectionPhase.disconnected);
    expect(h.view.failure, isNull);
  });

  test('内核受理请求却从不再推快照：重新同步回旧快照 → 5 s 判 nativeUnresponsive', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)..resyncResult = () => _s(version: 1);
    final t0 = h.now;
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 4, milliseconds: 999));
    expect(h.outcomes[1], isNull);
    w.run(const Duration(milliseconds: 1));
    expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    expect(h.now.difference(t0), const Duration(seconds: 5));
    _expectOneOutcomeEach(h, [1]);
    expect(h.view.phase, ConnectionPhase.disconnected);
    expect(h.view.failure, const NativeUnresponsive());
  });

  test('重新同步调用本身也不返回：5 s + 3 s 宽限后判 nativeUnresponsive', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)..resyncHangs = true;
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 7, milliseconds: 999));
    expect(h.outcomes[1], isNull, reason: '5 s + 3 s 之前不判');
    w.run(const Duration(milliseconds: 1));
    expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    _expectOneOutcomeEach(h, [1]);
  });

  test('重新同步取回追上的快照：不判失败，请求正常终结', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)
      ..resyncResult = () => _s(
        version: 2,
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        appliedSeq: 1,
        rev: 1,
      );
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 30));
    expect(h.outcomes[1], [const RequestSucceeded()]);
    expect(h.view.failure, isNull);
    expect(h.view.phase, ConnectionPhase.connected);
  });

  test('状态流失联：10 s 内所有未终结请求 failed，恢复后失败清除', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)..sendFailure = const PlatformFailure('unavailable', '');
    h.link(KernelLink.lost);
    h.intent(1, Desired.on);
    w.pump();
    expect(h.outcomes[1], [
      const RequestFailed(PlatformFailure('unavailable', '')),
    ]);
    w.sendFailure = null;
    h.intent(2, Desired.off);
    w.run(const Duration(seconds: 60));
    expect(h.outcomes[2], hasLength(1));
    expect(h.outcomes[2]!.single, isA<RequestFailed>());
    expect(h.view.failure, isNotNull);
    h.link(KernelLink.connected);
    expect(h.view.failure, isNull);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('从不收到首个快照：resolving 期间的意图 10 s 内 failed', () {
    final h = MachineHarness();
    final w = _World(h);
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 10));
    expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    expect(h.view.phase, ConnectionPhase.resolving);
  });

  test('内核一直 starting：机器不自作主张终结，等协调器的 startTimeout 失败到达', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h);
    h.intent(1, Desired.on);
    w.pump();
    h.snap(
      _s(
        version: 2,
        status: KernelStatus.starting,
        attempt: 1,
        desired: Desired.on,
        appliedSeq: 1,
      ),
    );
    w.run(const Duration(seconds: 29));
    expect(h.outcomes[1], isNull);
    expect(h.view.phase, ConnectionPhase.connecting);
    h.snap(
      _s(
        version: 3,
        attempt: 1,
        appliedSeq: 1,
        failure: const KernelFailure(
          code: KernelFailureCode.startTimeout,
          message: '',
          attempt: 1,
          seq: 1,
        ),
      ),
    );
    expect(h.outcomes[1], [const RequestFailed(StartTimeout())]);
    expect(h.view.failure, const StartTimeout());
    _expectOneOutcomeEach(h, [1]);
  });

  test('准备失败与 RPC 失败：不挂起', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)..prepareFailure = const ConfigMissing();
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 1));
    w.prepareFailure = null;
    w.sendFailure = const PlatformFailure('timeout', '');
    h.intent(2, Desired.on);
    w.run(const Duration(seconds: 1));
    expect(h.outcomes[1], [const RequestFailed(ConfigMissing())]);
    expect(h.outcomes[2], [
      const RequestFailed(PlatformFailure('timeout', '')),
    ]);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('纪元变化：在途请求 interrupted，随后的新意图在新基线上正常完成', () {
    final h = MachineHarness()..snap(_s(appliedSeq: 3));
    final w = _World(h);
    h.intent(1, Desired.on);
    w.pump();
    h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 0));
    expect(h.outcomes[1], [const RequestInterrupted()]);
    h.intent(2, Desired.on);
    w.pump();
    expect(h.sends.last.request.seq, 1);
    expect(h.sends.last.request.epoch, 'e2');
    h.snap(
      _s(
        epoch: 'e2',
        version: 2,
        status: KernelStatus.started,
        attempt: 1,
        desired: Desired.on,
        appliedSeq: 1,
        rev: 1,
      ),
    );
    expect(h.outcomes[2], [const RequestSucceeded()]);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('托盘退出场景：on 被 off 取代，off 之后又被 on 取代——每个都有结果，最新 off 可等待', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h);
    h.intent(1, Desired.on);
    h.intent(2, Desired.off);
    w.pump();
    h.snap(_s(version: 2, attempt: 0, appliedSeq: 1));
    expect(h.outcomes[1], [const RequestSuperseded()]);
    expect(h.outcomes[2], [const RequestSucceeded()]);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('stale / wrongEpoch 被反复拒绝：有界地失败', () {
    final h = MachineHarness()..snap(_s());
    final w = _World(h)
      ..receipt = (s) => MachineHarness.rejected(
        RequestRejection.stale,
        epoch: s.request.epoch,
        appliedSeq: s.request.seq + 5,
      );
    h.intent(1, Desired.off);
    w.run(const Duration(seconds: 30));
    expect(h.outcomes[1]!.single, isA<RequestFailed>());
    expect(h.sends.length, lessThan(10));
    _expectOneOutcomeEach(h, [1]);
  });
}
