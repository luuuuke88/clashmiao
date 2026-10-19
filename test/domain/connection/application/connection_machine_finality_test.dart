import 'dart:math';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/machine_harness.dart';

// 「每个请求最终都有终结结果」（计划 P3）：脚本化的假世界 + 可控时钟。
// 世界按脚本执行机器给出的动作（准备、发送、重新同步），时间只通过
// nextWake → Tick 推进。

/// 额外记录每个意图终结时刻的驱动器。
class _TimedHarness extends MachineHarness {
  final _settledAt = <int, DateTime>{};

  DateTime? settledAt(int id) => _settledAt[id];

  @override
  Transition feed(MachineEvent e) {
    final t = super.feed(e);
    for (final a in t.actions.whereType<SettleRequest>()) {
      _settledAt[a.id] ??= e.now;
    }
    return t;
  }
}

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
    final h = _TimedHarness()..snap(_s());
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
    final h = _TimedHarness()..snap(_s());
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
    final h = _TimedHarness()..snap(_s());
    final w = _World(h)..resyncHangs = true;
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 7, milliseconds: 999));
    expect(h.outcomes[1], isNull, reason: '5 s + 3 s 之前不判');
    w.run(const Duration(milliseconds: 1));
    expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    _expectOneOutcomeEach(h, [1]);
  });

  test('重新同步取回追上的快照：不判失败，请求正常终结', () {
    final h = _TimedHarness()..snap(_s());
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

  test('状态流失联、重同步也失败：不发送，10 s 内所有未终结请求 failed，恢复后失败清除', () {
    final h = _TimedHarness()..snap(_s());
    final w = _World(h);
    h.link(KernelLink.lost);
    h.intent(1, Desired.on);
    h.intent(2, Desired.off);
    w.run(const Duration(seconds: 60));
    expect(h.sends, isEmpty, reason: '失联后没有有效的重同步结果，绝不发送');
    expect(h.outcomes[1], [const RequestSuperseded()]);
    expect(h.outcomes[2], [const RequestFailed(NativeUnresponsive())]);
    expect(h.view.failure, const NativeUnresponsive());
    h.link(KernelLink.connected);
    expect(h.view.failure, isNull);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('状态流失联但 current() 可用：重同步后按新基线发送并正常完成', () {
    final h = _TimedHarness()..snap(_s(appliedSeq: 2));
    final w = _World(h)..resyncResult = () => _s(version: 2, appliedSeq: 4);
    h.link(KernelLink.lost);
    h.intent(1, Desired.off);
    w.pump();
    expect(h.sends.single.request.seq, 5);
    h.snap(_s(version: 3, appliedSeq: 5));
    expect(h.outcomes[1], [const RequestSucceeded()]);
    _expectOneOutcomeEach(h, [1]);
  });

  test('从不收到首个快照：resolving 期间的意图 10 s 内 failed', () {
    final h = _TimedHarness();
    final w = _World(h);
    h.intent(1, Desired.on);
    w.run(const Duration(seconds: 10));
    expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    expect(h.view.phase, ConnectionPhase.resolving);
  });

  test('内核一直 starting：机器不自作主张终结，等协调器的 startTimeout 失败到达', () {
    final h = _TimedHarness()..snap(_s());
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
    final h = _TimedHarness()..snap(_s());
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
    final h = _TimedHarness()..snap(_s(appliedSeq: 3));
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
    final h = _TimedHarness()..snap(_s());
    final w = _World(h);
    h.intent(1, Desired.on);
    h.intent(2, Desired.off);
    w.pump();
    h.snap(_s(version: 2, attempt: 0, appliedSeq: 1));
    expect(h.outcomes[1], [const RequestSuperseded()]);
    expect(h.outcomes[2], [const RequestSucceeded()]);
    _expectOneOutcomeEach(h, [1, 2]);
  });

  test('stale 被反复拒绝：有界地失败', () {
    final h = _TimedHarness()..snap(_s());
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

  test('wrongEpoch 被反复拒绝（每次重同步都取回又一个新纪元）：有界地失败', () {
    final h = _TimedHarness()..snap(_s());
    var n = 1;
    final w = _World(h)
      ..receipt = ((s) => MachineHarness.rejected(
        RequestRejection.wrongEpoch,
        epoch: 'x${++n}',
      ))
      ..resyncResult = () => _s(epoch: 'x$n');
    h.intent(1, Desired.off);
    w.run(const Duration(seconds: 60));
    expect(h.outcomes[1]!.single, isA<RequestFailed>());
    expect(
      h.sends.map((s) => s.request.epoch).toSet(),
      hasLength(h.sends.length),
    );
    expect(h.sends.length, ConnectionTiming.maxResends + 1);
    _expectOneOutcomeEach(h, [1]);
  });

  group('wrongEpoch 之后的重同步异常（独立截止时间）', () {
    _World wrongEpochWorld(MachineHarness h) => _World(h)
      ..receipt = (s) => s.request.epoch == 'e1'
          ? MachineHarness.rejected(RequestRejection.wrongEpoch, epoch: 'e2')
          : MachineHarness.accepted(s.request.seq, epoch: s.request.epoch);

    test('重同步失败：有界重试后 failed，且未重发', () {
      final h = _TimedHarness()..snap(_s());
      final w = wrongEpochWorld(h);
      final t0 = h.now;
      h.intent(1, Desired.off);
      w.run(const Duration(seconds: 60));
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(h.sends, hasLength(1));
      expect(h.resyncs, ConnectionTiming.maxResyncAttempts);
      expect(
        h.settledAt(1)!.difference(t0),
        lessThan(ConnectionTiming.resyncWaitTimeout),
      );
      _expectOneOutcomeEach(h, [1]);
    });

    test('重同步只取回旧纪元快照：有界重试后 failed', () {
      final h = _TimedHarness()..snap(_s());
      var v = 1;
      final w = wrongEpochWorld(h)..resyncResult = () => _s(version: ++v);
      h.intent(1, Desired.off);
      w.run(const Duration(seconds: 60));
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(h.sends, hasLength(1));
      _expectOneOutcomeEach(h, [1]);
    });

    test('重同步一直不返回：10 s 截止时间到期 failed', () {
      final h = _TimedHarness()..snap(_s());
      final w = wrongEpochWorld(h)..resyncHangs = true;
      final t0 = h.now;
      h.intent(1, Desired.off);
      w.run(const Duration(seconds: 60));
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(
        h.settledAt(1)!.difference(t0),
        ConnectionTiming.resyncWaitTimeout,
      );
      _expectOneOutcomeEach(h, [1]);
    });

    test('重同步取回新纪元：按新基线重发并 succeeded', () {
      final h = _TimedHarness()..snap(_s());
      final w = wrongEpochWorld(h)
        ..resyncResult = () => _s(epoch: 'e2', appliedSeq: 3);
      h.intent(1, Desired.off);
      w.pump();
      expect(h.sends.last.request.epoch, 'e2');
      expect(h.sends.last.request.seq, 4);
      h.snap(_s(epoch: 'e2', version: 2, appliedSeq: 4));
      expect(h.outcomes[1], [const RequestSucceeded()]);
      _expectOneOutcomeEach(h, [1]);
    });
  });

  test('随机世界（固定种子 300 条）：每个意图都在有界时间内恰好终结一次', () {
    for (var seed = 0; seed < 300; seed++) {
      _RandomWorld(seed).runAndCheck();
    }
  });
}

/// 随机行为的假原生：回执延迟、RPC 抛错、stale / wrongEpoch、内核重启（新纪元）、
/// 状态流失联与恢复、快照不推送、重同步失败/悬挂/取回旧快照。内核在受理时立即
/// 收敛到目标（或写入归属于该 seq 的失败），只是快照可能迟到或不到——这样「机器
/// 等协调器 30 s 启动超时」的合法等待不会出现在这里。
class _RandomWorld {
  _RandomWorld(this.seed) : rnd = Random(seed), h = _TimedHarness();

  final int seed;
  final Random rnd;
  final _TimedHarness h;

  // 内核模型。
  var _epochN = 1;
  String get _epoch => 'r$_epochN';
  var _version = 1;
  var _applied = 0;
  var _attempt = 0;
  var _status = KernelStatus.stopped;
  var _desired = Desired.off;
  int? _rev;
  KernelFailure? _failure;
  var _linkUp = true;

  final _queue = <(DateTime, int, void Function())>[];
  var _order = 0;
  int _cursor = 0;
  final _raisedAt = <int, DateTime>{};

  KernelSnapshot _current() => _s(
    epoch: _epoch,
    version: _version,
    status: _status,
    attempt: _attempt,
    desired: _desired,
    appliedSeq: _applied,
    rev: _rev,
    failure: _failure,
  );

  void _later(Duration d, void Function() f) {
    _queue.add((h.now.add(d), _order++, f));
  }

  Duration _jitter() => Duration(milliseconds: rnd.nextInt(2500));

  void _push() {
    if (_linkUp && rnd.nextInt(5) != 0) {
      final s = _current();
      _later(_jitter(), () => h.snap(s));
    }
  }

  void _restart() {
    _epochN++;
    _version = 1;
    _applied = 0;
    _attempt = 0;
    _status = KernelStatus.stopped;
    _desired = Desired.off;
    _rev = null;
    _failure = null;
    _push();
  }

  void _apply(SendRequest a) {
    final r = a.request;
    if (r.epoch != _epoch) {
      h.receipt(
        a.id,
        MachineHarness.rejected(
          RequestRejection.wrongEpoch,
          epoch: _epoch,
          appliedSeq: _applied,
        ),
      );
      return;
    }
    if (r.seq <= _applied) {
      h.receipt(
        a.id,
        MachineHarness.rejected(
          RequestRejection.stale,
          epoch: _epoch,
          appliedSeq: _applied,
        ),
      );
      return;
    }
    _applied = r.seq;
    _version++;
    if (r.desired == Desired.on && rnd.nextInt(5) == 0) {
      _attempt++;
      _status = KernelStatus.stopped;
      _desired = Desired.off;
      _failure = KernelFailure(
        code: KernelFailureCode.startService,
        message: 'boom',
        attempt: _attempt,
        seq: r.seq,
      );
    } else if (r.desired == Desired.on) {
      if (_status != KernelStatus.started || _rev != r.launch!.configRevision) {
        _attempt++;
      }
      _status = KernelStatus.started;
      _desired = Desired.on;
      _rev = r.launch!.configRevision;
    } else {
      _status = KernelStatus.stopped;
      _desired = Desired.off;
      _rev = null;
    }
    h.receipt(a.id, MachineHarness.accepted(r.seq, epoch: _epoch));
    _push();
  }

  void _pump() {
    while (_cursor < h.actions.length) {
      final a = h.actions[_cursor++];
      switch (a) {
        case PrepareLaunch():
          final id = a.id;
          final fail = rnd.nextInt(10) == 0;
          final rev = 1 + rnd.nextInt(3);
          _later(_jitter(), () {
            if (fail) {
              h.prepareFailed(id, const ConfigMissing());
            } else {
              h.prepared(id, revision: rev);
            }
          });
        case SendRequest():
          final roll = rnd.nextInt(10);
          if (roll == 0) {
            _later(
              _jitter(),
              () => h.sendFailed(a.id, const PlatformFailure('timeout', '')),
            );
          } else if (roll == 1) {
            // 回执丢失：既无回执也无失败（只能靠截止时间）。
            if (rnd.nextBool()) _later(_jitter(), () => _applySilently(a));
          } else {
            _later(_jitter(), () => _apply(a));
          }
        case Resync():
          final roll = rnd.nextInt(6);
          if (roll == 0) {
            _later(_jitter(), h.resyncFailed);
          } else if (roll == 1) {
            // 悬挂：永不返回。
          } else if (roll == 2) {
            final old = _current().copyWith(version: max(1, _version - 1));
            _later(_jitter(), () => h.snap(old, fromResync: true));
          } else {
            _later(_jitter(), () => h.snap(_current(), fromResync: true));
          }
        case RunEffect() || SettleRequest():
          break;
      }
    }
  }

  void _applySilently(SendRequest a) {
    // 内核处理了请求，但回执没回来；状态变化照常推送（可能被丢弃）。
    if (a.request.epoch == _epoch && a.request.seq > _applied) {
      _applied = a.request.seq;
      _version++;
      if (a.request.desired == Desired.on) {
        _attempt++;
        _status = KernelStatus.started;
        _desired = Desired.on;
        _rev = a.request.launch!.configRevision;
      } else {
        _status = KernelStatus.stopped;
        _desired = Desired.off;
        _rev = null;
      }
      _push();
    }
  }

  void runAndCheck() {
    final ctx = 'seed=$seed';
    h.snap(_current());
    // 剧本：随机时刻的用户意图、链路变化、内核重启。
    final script = <(Duration, void Function())>[];
    var t = Duration.zero;
    var nextId = 1;
    for (var i = 0; i < 12; i++) {
      t += Duration(milliseconds: rnd.nextInt(6000));
      final roll = rnd.nextInt(10);
      if (roll < 6) {
        final id = nextId++;
        final desired = rnd.nextBool() ? Desired.on : Desired.off;
        script.add((
          t,
          () {
            _raisedAt[id] = h.now;
            h.intent(id, desired);
          },
        ));
      } else if (roll < 8) {
        script.add((
          t,
          () {
            _linkUp = !_linkUp;
            h.link(_linkUp ? KernelLink.connected : KernelLink.lost);
            if (_linkUp) _push();
          },
        ));
      } else {
        script.add((t, _restart));
      }
    }
    final start = h.now;
    for (final (at, f) in script) {
      _later(at, f);
    }
    // 尾声：恢复链路（之后的世界仍随机出错）。
    _later(t + const Duration(seconds: 1), () {
      if (!_linkUp) {
        _linkUp = true;
        h.link(KernelLink.connected);
      }
    });

    final end = start.add(t + const Duration(seconds: 300));
    for (var guard = 0; guard < 100000; guard++) {
      _pump();
      _queue.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      final wake = h.last.nextWake;
      final due = _queue.isEmpty ? null : _queue.first.$1;
      DateTime? next;
      if (wake != null) next = wake;
      if (due != null && (next == null || due.isBefore(next))) next = due;
      if (next == null || next.isAfter(end)) break;
      if (next.isAfter(h.now)) h.now = next;
      if (due != null && !due.isAfter(h.now)) {
        final item = _queue.removeAt(0);
        item.$3();
      } else {
        h.feed(Tick(now: h.now));
      }
    }
    _pump();

    for (final id in _raisedAt.keys) {
      expect(h.outcomes[id], hasLength(1), reason: '$ctx 意图 #$id 必须恰好终结一次');
      final settled = h.settledAt(id)!;
      expect(
        settled.difference(_raisedAt[id]!),
        lessThan(const Duration(seconds: 120)),
        reason: '$ctx 意图 #$id 终结超时',
      );
    }
    expect(h.state.requests, isEmpty, reason: '$ctx 请求表必须清空');
  }
}
