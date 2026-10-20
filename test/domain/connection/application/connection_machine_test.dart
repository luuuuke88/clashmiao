import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/application/connection_timing.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:clashmiao/domain/connection/model/request_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/machine_harness.dart';

const _stopped = KernelStatus.stopped;
const _starting = KernelStatus.starting;
const _started = KernelStatus.started;
const _stopping = KernelStatus.stopping;
const _on = Desired.on;
const _off = Desired.off;

KernelSnapshot _s({
  String epoch = 'e1',
  int version = 1,
  KernelStatus status = _stopped,
  int attempt = 0,
  Desired desired = _off,
  DesiredSource source = DesiredSource.system,
  int appliedSeq = 0,
  int? rev,
  KernelFailure? failure,
  bool replay = false,
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
  selectionsReplayNeeded: replay,
);

KernelFailure _kf(
  KernelFailureCode code, {
  int attempt = 1,
  int? seq,
  String message = '',
}) => KernelFailure(code: code, message: message, attempt: attempt, seq: seq);

/// 连到「已连接」的常用起手式：stopped 快照 → 用户点连接 → 准备完成 → 内核受理并启动。
MachineHarness _connected({int rev = 1, int seq = 1, int attempt = 1}) {
  final h = MachineHarness();
  h.snap(_s());
  h.intent(1, _on);
  h.prepared(1, revision: rev);
  h.receipt(1, MachineHarness.accepted(seq));
  h.snap(
    _s(
      version: 2,
      status: _started,
      attempt: attempt,
      desired: _on,
      source: DesiredSource.app,
      appliedSeq: seq,
      rev: rev,
    ),
  );
  return h;
}

void main() {
  group('phase 表（spec §5，逐行）', () {
    test('1. 尚无快照 → resolving，isBusy', () {
      final h = MachineHarness();
      final t = const ConnectionMachine().reduce(
        h.state,
        Tick(now: h.now.add(const Duration(seconds: 1))),
      );
      expect(t.snapshot.phase, ConnectionPhase.resolving);
      expect(t.snapshot.isBusy, isTrue);
      expect(t.snapshot.origin, isNull);
      expect(t.snapshot.startedAt, isNull);
    });

    test('1b. resolving 期间点击：意图被记录，phase 仍是 resolving，快照到达后才发送', () {
      final h = MachineHarness();
      h.intent(1, _on);
      expect(h.view.phase, ConnectionPhase.resolving);
      expect(h.lastActions.whereType<PrepareLaunch>(), hasLength(1));
      h.prepared(1);
      expect(h.sends, isEmpty, reason: '没有纪元与 seq 基线，不能发送');
      h.snap(_s(appliedSeq: 4));
      expect(h.sends, hasLength(1));
      expect(h.sends.single.request.seq, 5, reason: 'seq 基线 = appliedSeq + 1');
      expect(h.sends.single.request.epoch, 'e1');
      expect(h.view.phase, ConnectionPhase.connecting);
    });

    test('2a. 未确认的 on 请求 → connecting（即便快照仍是 disconnected）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      expect(h.view.phase, ConnectionPhase.connecting, reason: '准备期间就显示');
      h.prepared(1);
      expect(h.view.phase, ConnectionPhase.connecting);
      h.receipt(1, MachineHarness.accepted(1));
      expect(h.view.phase, ConnectionPhase.connecting, reason: '受理 ≠ 确认');
    });

    test('2b. 未确认的 off 请求 → disconnecting（即便快照仍是 connected）', () {
      final h = _connected();
      h.intent(2, _off);
      expect(h.view.phase, ConnectionPhase.disconnecting);
      expect(h.view.isBusy, isTrue);
    });

    test('2c. 请求被确认后改由快照决定：appliedSeq 追上 → 不再按未确认处理', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(
        _s(
          version: 2,
          status: _starting,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
        ),
      );
      expect(h.view.phase, ConnectionPhase.connecting);
    });

    test('3. desired=on、started、revision 与最新请求一致 → connected', () {
      final h = _connected(rev: 7);
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.view.isBusy, isFalse);
      expect(h.view.origin, DesiredSource.app);
    });

    test('3b. 没有本地请求（外部启动、activeConfigRevision 为空）也算 connected', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 1,
            desired: _on,
            source: DesiredSource.tile,
          ),
        );
      expect(h.view.phase, ConnectionPhase.connected);
    });

    test('2d. 未确认的 on 请求优先于快照：started 时也显示 connecting（新配置请求）', () {
      final h = _connected(rev: 1);
      final t0 = h.view.startedAt;
      h.intent(2, _on, reason: RequestReason.applyConfig);
      expect(h.view.phase, ConnectionPhase.connecting);
      h.prepared(2, revision: 2);
      expect(h.view.phase, ConnectionPhase.connecting);
      h.receipt(2, MachineHarness.accepted(2));
      expect(h.view.phase, ConnectionPhase.connecting, reason: '受理 ≠ 确认');
      expect(h.view.startedAt, t0, reason: 'startedAt 的保留与 phase 无关');
    });

    test('2e. 未确认的 on 请求即便 revision 与运行实例相同，也显示 connecting', () {
      final h = _connected(rev: 4);
      h.intent(2, _on, reason: RequestReason.applyConfig);
      h.prepared(2, revision: 4);
      h.receipt(2, MachineHarness.accepted(2));
      expect(h.view.phase, ConnectionPhase.connecting);
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 4,
        ),
      );
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.outcomes[2], [const RequestSucceeded()]);
    });

    test('2f. started 时未确认的 off 请求 → disconnecting（与 revision 无关）', () {
      final h = _connected(rev: 4);
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      expect(h.view.phase, ConnectionPhase.disconnecting);
    });

    test('4b. 新配置已被受理、但运行实例仍是旧 revision → reconnecting，换上后 connected', () {
      final h = _connected(rev: 1);
      h.intent(2, _on, reason: RequestReason.applyConfig);
      h.prepared(2, revision: 2);
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
        ),
      );
      expect(h.view.phase, ConnectionPhase.reconnecting);
      h.snap(
        _s(
          version: 4,
          status: _started,
          attempt: 2,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 2,
        ),
      );
      expect(h.view.phase, ConnectionPhase.connected);
    });

    test('4c. 已连接过的会话重载中间态（status≠started，desired 仍 on）→ connecting，'
        'startedAt 保留', () {
      final h = _connected();
      final t0 = h.view.startedAt;
      expect(t0, isNotNull);
      for (final (i, st) in [_stopping, _stopped, _starting].indexed) {
        h.snap(
          _s(
            version: 3 + i,
            status: st,
            attempt: 2,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 1,
            rev: 1,
          ),
        );
        expect(h.view.phase, ConnectionPhase.connecting, reason: st.name);
        expect(h.view.startedAt, t0, reason: st.name);
      }
    });

    test('4d. attached 会话的重载中间态同样是 connecting（不因已建立而改为 reconnecting）', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 4,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 3,
            rev: 2,
          ),
        );
      expect(h.state.attached, isTrue);
      h.snap(
        _s(
          version: 2,
          status: _starting,
          attempt: 5,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 3,
          rev: 2,
        ),
      );
      expect(h.view.phase, ConnectionPhase.connecting);
    });

    test('5. desired=on 其他 → connecting（无论是否建立过会话）', () {
      for (final st in [_stopped, _starting, _stopping]) {
        final h = MachineHarness()
          ..snap(
            _s(
              status: st,
              attempt: 1,
              desired: _on,
              source: DesiredSource.tile,
            ),
          );
        expect(h.view.phase, ConnectionPhase.connecting, reason: st.name);
      }
    });

    test('6. desired=off 且 stopped → disconnected', () {
      final h = MachineHarness()..snap(_s());
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, isNull);
      expect(h.view.isBusy, isFalse);
    });

    test('6b. disconnected 带 failure：lastFailure 属于最近请求（seq）', () {
      final h = MachineHarness()
        ..snap(
          _s(
            attempt: 3,
            appliedSeq: 6,
            failure: _kf(KernelFailureCode.startTimeout, attempt: 2, seq: 6),
          ),
        );
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, const StartTimeout());
    });

    test('6c. disconnected 带 failure：lastFailure 属于本纪元最近 attempt', () {
      final h = MachineHarness()
        ..snap(
          _s(
            attempt: 4,
            appliedSeq: 9,
            failure: _kf(
              KernelFailureCode.kernelExited,
              attempt: 4,
              message: 'boom',
            ),
          ),
        );
      expect(
        h.view.failure,
        const KernelStartFailed(KernelFailureCode.kernelExited, 'boom'),
      );
    });

    test('6d. 更早 attempt / 其它 seq 的旧失败不展示', () {
      final h = MachineHarness()
        ..snap(
          _s(
            attempt: 5,
            appliedSeq: 9,
            failure: _kf(KernelFailureCode.startTimeout, attempt: 3, seq: 6),
          ),
        );
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, isNull);
    });

    test('7. desired=off 其他 → disconnecting（普通失败不展示）', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _stopping,
            attempt: 1,
            appliedSeq: 1,
            failure: _kf(KernelFailureCode.startService, attempt: 1, seq: 1),
          ),
        );
      expect(h.view.phase, ConnectionPhase.disconnecting);
      expect(h.view.failure, isNull);
    });

    test(
      '7b. disconnecting + kernelUnresponsive → 带 failure（按钮可点 = 重发 off）',
      () {
        final h = MachineHarness()
          ..snap(
            _s(
              status: _stopping,
              attempt: 1,
              appliedSeq: 2,
              failure: _kf(
                KernelFailureCode.kernelUnresponsive,
                attempt: 1,
                seq: 2,
              ),
            ),
          );
        expect(h.view.phase, ConnectionPhase.disconnecting);
        expect(h.view.failure, const KernelUnresponsive());
      },
    );

    test('origin 跟随快照 source；本地有未确认请求时为 app', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 1,
            desired: _on,
            source: DesiredSource.tile,
          ),
        );
      expect(h.view.origin, DesiredSource.tile);
      h.intent(1, _off);
      expect(h.view.origin, DesiredSource.app);
    });

    test('isBusy：仅 connected / disconnected 为 false', () {
      for (final p in ConnectionPhase.values) {
        final busy =
            p != ConnectionPhase.connected && p != ConnectionPhase.disconnected;
        expect(ConnectionSnapshot(phase: p).isBusy, busy, reason: p.name);
      }
    });

    test('失联期间 phase 保持最后值并标记 stale，恢复后清除', () {
      final h = _connected();
      h.link(KernelLink.lost);
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.view.stale, isTrue);
      h.link(KernelLink.connected);
      expect(h.view.stale, isFalse);
    });
  });

  group('副作用（spec §5，按 (epoch, attempt) 去重）', () {
    test('用户 connect 进入 started：触觉 heavy + 评分请求 + startedAt=now，各一次', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.now = h.now.add(const Duration(seconds: 3));
      final t0 = h.now;
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
      );
      expect(h.effectsOf(SideEffectKind.hapticHeavy), hasLength(1));
      expect(h.effectsOf(SideEffectKind.requestReview), hasLength(1));
      expect(h.effectsOf(SideEffectKind.hapticHeavy).single.attempt, 1);
      expect(h.effectsOf(SideEffectKind.hapticHeavy).single.epoch, 'e1');
      expect(h.view.startedAt, t0);

      // 同一 attempt 的重复快照（version 递增、字段相同或重放标志变化）不再触发。
      for (var v = 3; v < 8; v++) {
        h.now = h.now.add(const Duration(seconds: 1));
        h.snap(
          _s(
            version: v,
            status: _started,
            attempt: 1,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 1,
            rev: 1,
            replay: v.isEven,
          ),
        );
      }
      expect(h.effectsOf(SideEffectKind.hapticHeavy), hasLength(1));
      expect(h.effectsOf(SideEffectKind.requestReview), hasLength(1));
      expect(h.view.startedAt, t0, reason: 'startedAt 不被重复快照刷新');
    });

    test('重复快照（同 version）整体无副作用、状态不变', () {
      final h = _connected();
      final beforeView = h.view;
      final beforeState = h.state;
      final n = h.actions.length;
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
      );
      expect(h.actions.length, n);
      expect(h.view, beforeView);
      expect(
        identical(h.state, beforeState) ||
            h.state.startedAt == beforeState.startedAt,
        isTrue,
      );
    });

    test('冷启动挂上运行中隧道（attached）：无触觉/评分，startedAt=null', () {
      final h = MachineHarness()
        ..snap(
          _s(
            version: 9,
            status: _started,
            attempt: 4,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 3,
            rev: 2,
          ),
        );
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.view.startedAt, isNull);
      expect(h.effectsOf(SideEffectKind.hapticHeavy), isEmpty);
      expect(h.effectsOf(SideEffectKind.requestReview), isEmpty);
    });

    test('attached 之后的重载不会补上 startedAt，也不触觉', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 4,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 3,
            rev: 2,
          ),
        );
      h.snap(
        _s(
          version: 2,
          status: _starting,
          attempt: 5,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 3,
          rev: 2,
        ),
      );
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 5,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 3,
          rev: 2,
        ),
      );
      expect(h.view.startedAt, isNull);
      expect(
        h.effects.where((e) => e.kind != SideEffectKind.replaySelections),
        isEmpty,
      );
    });

    test('attached 后用户断开：stopped 时清空 attached，之后重新连接得到 startedAt', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 4,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 3,
            rev: 2,
          ),
        );
      h.snap(
        _s(
          version: 2,
          status: _stopped,
          attempt: 4,
          source: DesiredSource.tile,
          appliedSeq: 3,
        ),
      );
      h.now = h.now.add(const Duration(minutes: 1));
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 5,
          desired: _on,
          source: DesiredSource.tile,
          appliedSeq: 3,
          rev: 2,
        ),
      );
      expect(h.view.startedAt, h.now);
    });

    test('磁贴来源启动：startedAt=now，无触觉/评分', () {
      final h = MachineHarness()..snap(_s());
      h.now = h.now.add(const Duration(seconds: 5));
      h.snap(
        _s(
          version: 2,
          status: _starting,
          attempt: 1,
          desired: _on,
          source: DesiredSource.tile,
        ),
      );
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.tile,
        ),
      );
      expect(h.view.startedAt, h.now);
      expect(h.effectsOf(SideEffectKind.hapticHeavy), isEmpty);
      expect(h.effectsOf(SideEffectKind.requestReview), isEmpty);
    });

    for (final src in [DesiredSource.shortcut, DesiredSource.boot]) {
      test('${src.name} 来源启动：startedAt=now，无触觉/评分', () {
        final h = MachineHarness()..snap(_s());
        h.snap(
          _s(
            version: 2,
            status: _started,
            attempt: 1,
            desired: _on,
            source: src,
          ),
        );
        expect(h.view.startedAt, h.now);
        expect(h.effects, isEmpty);
      });
    }

    test('source=app 但请求不是本进程的用户 connect（reason=applyConfig）：无触觉/评分', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on, reason: RequestReason.applyConfig);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
      );
      expect(h.view.startedAt, h.now);
      expect(h.effects.map((e) => e.kind), [
        SideEffectKind.markSystemProxyDirty,
      ], reason: '只有发送时的脏标记，没有触觉/评分');
    });

    test('source=app 但 seq 不是本进程发出的（Dart 引擎重建前的请求）：无触觉/评分', () {
      final h = MachineHarness()..snap(_s(appliedSeq: 5));
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 5,
          rev: 1,
        ),
      );
      expect(h.effects, isEmpty);
      expect(h.view.startedAt, h.now);
    });

    test('重载中间态不清 startedAt，重载完成也不重置、不再触觉', () {
      final h = _connected();
      final t0 = h.view.startedAt!;
      h.intent(2, _on, reason: RequestReason.applyConfig);
      h.prepared(2, revision: 2);
      h.receipt(2, MachineHarness.accepted(2));
      var v = 3;
      for (final st in [_stopping, _stopped, _starting, _started]) {
        h.now = h.now.add(const Duration(seconds: 1));
        h.snap(
          _s(
            version: v++,
            status: st,
            attempt: 2,
            desired: _on,
            source: DesiredSource.app,
            appliedSeq: 2,
            rev: st == _started ? 2 : 1,
          ),
        );
        expect(h.view.startedAt, t0, reason: st.name);
      }
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.effectsOf(SideEffectKind.hapticHeavy), hasLength(1));
      expect(h.effectsOf(SideEffectKind.requestReview), hasLength(1));
    });

    test('手选重放：任意 started 且 selectionsReplayNeeded，每 attempt 一次', () {
      final h = _connected();
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
          replay: true,
        ),
      );
      h.snap(
        _s(
          version: 4,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
          replay: true,
        ),
      );
      expect(h.effectsOf(SideEffectKind.replaySelections), hasLength(1));
      expect(h.effectsOf(SideEffectKind.replaySelections).single.attempt, 1);
      // 新 attempt（网络切换重载）再来一次。
      h.snap(
        _s(
          version: 5,
          status: _started,
          attempt: 2,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
          replay: true,
        ),
      );
      expect(h.effectsOf(SideEffectKind.replaySelections), hasLength(2));
      // 不要求重放时不触发；starting 时即便标志为真也不触发。
      h.snap(
        _s(
          version: 6,
          status: _starting,
          attempt: 3,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
          replay: true,
        ),
      );
      h.snap(
        _s(
          version: 7,
          status: _started,
          attempt: 3,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
      );
      expect(h.effectsOf(SideEffectKind.replaySelections), hasLength(2));
    });

    test('冷启动 attached 且要求重放：只重放，不触觉', () {
      final h = MachineHarness()
        ..snap(
          _s(
            status: _started,
            attempt: 2,
            desired: _on,
            source: DesiredSource.app,
            rev: 1,
            replay: true,
          ),
        );
      expect(h.effects.map((e) => e.kind), [SideEffectKind.replaySelections]);
    });

    test('用户 disconnect 进入 stopped：触觉 medium + 清系统代理脏标记，startedAt=null', () {
      final h = _connected();
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 3,
          status: _stopping,
          attempt: 1,
          desired: _off,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
        ),
      );
      expect(h.view.startedAt, isNotNull, reason: 'stopping 时尚未清');
      h.snap(
        _s(
          version: 4,
          status: _stopped,
          attempt: 1,
          desired: _off,
          source: DesiredSource.app,
          appliedSeq: 2,
        ),
      );
      expect(h.effectsOf(SideEffectKind.hapticMedium), hasLength(1));
      expect(h.effectsOf(SideEffectKind.clearSystemProxyDirty), hasLength(1));
      expect(h.view.startedAt, isNull);
      expect(h.view.phase, ConnectionPhase.disconnected);
      // 重复快照不再触发。
      h.snap(
        _s(
          version: 5,
          status: _stopped,
          attempt: 1,
          desired: _off,
          source: DesiredSource.app,
          appliedSeq: 2,
        ),
      );
      expect(h.effectsOf(SideEffectKind.hapticMedium), hasLength(1));
    });

    test('非用户断开（磁贴/系统撤销）：startedAt=null，但无触觉、不清脏标记', () {
      final h = _connected();
      h.snap(
        _s(
          version: 3,
          status: _stopped,
          attempt: 1,
          desired: _off,
          source: DesiredSource.tile,
          appliedSeq: 1,
        ),
      );
      expect(h.view.startedAt, isNull);
      expect(h.effectsOf(SideEffectKind.hapticMedium), isEmpty);
      expect(h.effectsOf(SideEffectKind.clearSystemProxyDirty), isEmpty);
    });

    test('发送 on 请求前置系统代理脏标记；off 不置', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      final kinds = h.lastActions
          .map((a) => a is RunEffect ? a.effect.kind : a.runtimeType)
          .toList();
      expect(kinds, [SideEffectKind.markSystemProxyDirty, SendRequest]);
      h.receipt(1, MachineHarness.accepted(1));
      h.intent(2, _off);
      expect(h.effectsOf(SideEffectKind.markSystemProxyDirty), hasLength(1));
    });

    test('新的致命 lastFailure 上报一次；非致命与冷启动已有的不上报', () {
      final h = MachineHarness()..snap(_s());
      h.snap(
        _s(
          version: 2,
          attempt: 1,
          failure: _kf(KernelFailureCode.startTimeout, attempt: 1),
        ),
      );
      expect(
        h.effectsOf(SideEffectKind.reportFailure),
        isEmpty,
        reason: 'startTimeout 非致命',
      );
      h.snap(
        _s(
          version: 3,
          attempt: 2,
          failure: _kf(
            KernelFailureCode.createService,
            attempt: 2,
            message: 'x',
          ),
        ),
      );
      expect(h.effectsOf(SideEffectKind.reportFailure), hasLength(1));
      expect(
        h.effectsOf(SideEffectKind.reportFailure).single.failure,
        const KernelStartFailed(KernelFailureCode.createService, 'x'),
      );
      h.snap(
        _s(
          version: 4,
          attempt: 2,
          failure: _kf(
            KernelFailureCode.createService,
            attempt: 2,
            message: 'x',
          ),
        ),
      );
      expect(
        h.effectsOf(SideEffectKind.reportFailure),
        hasLength(1),
        reason: '同一个失败不重复',
      );

      final attached = MachineHarness()
        ..snap(
          _s(
            attempt: 3,
            failure: _kf(KernelFailureCode.startService, attempt: 3),
          ),
        );
      expect(attached.effectsOf(SideEffectKind.reportFailure), isEmpty);
    });

    test('reportFailure 按 (epoch, attempt) 去重：同一 attempt 先后出现不同的致命失败只上报一次', () {
      final h = MachineHarness()..snap(_s());
      h.snap(
        _s(
          version: 2,
          attempt: 2,
          failure: _kf(KernelFailureCode.createService, attempt: 2, seq: 1),
        ),
      );
      h.snap(
        _s(
          version: 3,
          status: _stopping,
          attempt: 2,
          failure: _kf(KernelFailureCode.kernelUnresponsive, attempt: 2),
        ),
      );
      final reports = h.effectsOf(SideEffectKind.reportFailure).toList();
      expect(reports, hasLength(1));
      expect(reports.single.attempt, 2);
      expect(reports.single.epoch, 'e1');
      expect(
        reports.single.failure,
        const KernelStartFailed(KernelFailureCode.createService, ''),
      );
      expect(
        h.state.executedEffects,
        contains(('e1', 2, SideEffectKind.reportFailure)),
      );
      // 下一个 attempt 的致命失败照常上报。
      h.snap(
        _s(
          version: 4,
          attempt: 3,
          failure: _kf(KernelFailureCode.startService, attempt: 3),
        ),
      );
      expect(h.effectsOf(SideEffectKind.reportFailure), hasLength(2));
    });

    test('冷启动已有的致命失败占用其 (epoch, attempt)：同 attempt 的后续致命失败不再上报', () {
      final h = MachineHarness()
        ..snap(
          _s(
            attempt: 3,
            failure: _kf(KernelFailureCode.startService, attempt: 3),
          ),
        );
      h.snap(
        _s(
          version: 2,
          status: _stopping,
          attempt: 3,
          failure: _kf(KernelFailureCode.kernelUnresponsive, attempt: 3),
        ),
      );
      expect(h.effectsOf(SideEffectKind.reportFailure), isEmpty);
    });

    test('failureSeq：新失败递增、重复快照与冷启动旧失败不递增', () {
      final h = MachineHarness()
        ..snap(
          _s(
            attempt: 3,
            failure: _kf(KernelFailureCode.startService, attempt: 3),
          ),
        );
      expect(h.view.failure, isNotNull);
      expect(h.view.failureSeq, 0, reason: '冷启动旧失败只展示不提示');
      h.snap(
        _s(
          version: 2,
          attempt: 3,
          failure: _kf(KernelFailureCode.startService, attempt: 3),
        ),
      );
      expect(h.view.failureSeq, 0);
      h.snap(
        _s(
          version: 3,
          attempt: 4,
          failure: _kf(KernelFailureCode.startTimeout, attempt: 4),
        ),
      );
      expect(h.view.failureSeq, 1);
      h.snap(
        _s(
          version: 4,
          attempt: 4,
          failure: _kf(KernelFailureCode.startTimeout, attempt: 4),
        ),
      );
      expect(h.view.failureSeq, 1);
      h.snap(
        _s(
          version: 5,
          attempt: 5,
          failure: _kf(KernelFailureCode.startTimeout, attempt: 5),
        ),
      );
      expect(h.view.failureSeq, 2);
    });

    test('纪元变化：去重集合重置——新纪元里相同的 attempt 号可以再次触发', () {
      final h = MachineHarness()..snap(_s());
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.tile,
          replay: true,
        ),
      );
      expect(h.effectsOf(SideEffectKind.replaySelections), hasLength(1));
      h.snap(
        _s(
          epoch: 'e2',
          version: 1,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.tile,
          replay: true,
        ),
      );
      expect(h.effectsOf(SideEffectKind.replaySelections), hasLength(2));
      expect(h.effectsOf(SideEffectKind.replaySelections).last.epoch, 'e2');
    });
  });

  group('请求终结（spec §10.6 四种结果）', () {
    test('succeeded：connect 在 connected 时终结', () {
      final h = _connected();
      expect(h.outcomes[1], [const RequestSucceeded()]);
    });

    test('succeeded：disconnect 在 stopped 时终结，stopping 时尚未终结', () {
      final h = _connected();
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 3,
          status: _stopping,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
        ),
      );
      expect(h.outcomes[2], isNull);
      h.snap(
        _s(
          version: 4,
          status: _stopped,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 2,
        ),
      );
      expect(h.outcomes[2], [const RequestSucceeded()]);
    });

    test('succeeded：已 disconnected 时再发 off 照样发送并终结', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      expect(h.sends, hasLength(1));
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(_s(version: 2, source: DesiredSource.app, appliedSeq: 1));
      expect(h.outcomes[1], [const RequestSucceeded()]);
    });

    test('applyConfig：revision 相同 → 受理后立即 succeeded', () {
      final h = _connected(rev: 4);
      h.intent(2, _on, reason: RequestReason.applyConfig);
      h.prepared(2, revision: 4);
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 4,
        ),
      );
      expect(h.outcomes[2], [const RequestSucceeded()]);
    });

    test('failed：内核 lastFailure 属于该 seq', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(
        _s(
          version: 2,
          status: _starting,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
        ),
      );
      expect(h.outcomes[1], isNull);
      h.snap(
        _s(
          version: 3,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 1,
          failure: _kf(KernelFailureCode.startTimeout, attempt: 1, seq: 1),
        ),
      );
      expect(h.outcomes[1], [const RequestFailed(StartTimeout())]);
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, const StartTimeout());
      expect(h.view.failureSeq, 1);
    });

    test('failed：内核意外退出（lastFailure.seq 为空但属于当前 attempt、desired 被置 off）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(
        _s(
          version: 2,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 1,
          failure: _kf(KernelFailureCode.kernelExited, attempt: 1),
        ),
      );
      expect(h.outcomes[1], [
        const RequestFailed(
          KernelStartFailed(KernelFailureCode.kernelExited, ''),
        ),
      ]);
    });

    test('failed：off 请求遇 kernelUnresponsive（lastFailure.seq 属于该 off）', () {
      final h = _connected();
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 3,
          status: _stopping,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
          failure: _kf(
            KernelFailureCode.kernelUnresponsive,
            attempt: 1,
            seq: 2,
          ),
        ),
      );
      expect(h.outcomes[2], [const RequestFailed(KernelUnresponsive())]);
      expect(h.view.phase, ConnectionPhase.disconnecting);
      expect(h.view.failure, const KernelUnresponsive());
    });

    test('failed：准备失败（noActiveProfile）——不发送，failure 展示且 failureSeq 递增', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepareFailed(1, const NoActiveProfile());
      expect(h.sends, isEmpty);
      expect(h.outcomes[1], [const RequestFailed(NoActiveProfile())]);
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, const NoActiveProfile());
      expect(h.view.failureSeq, 1);
      // 下一次用户操作清掉本地失败。
      h.intent(2, _on);
      expect(h.view.failure, isNull);
    });

    test('failed：RPC 失败（request 抛错）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.sendFailed(1, const PlatformFailure('timeout', '2s'));
      expect(h.outcomes[1], [
        const RequestFailed(PlatformFailure('timeout', '2s')),
      ]);
      expect(h.view.failure, const PlatformFailure('timeout', '2s'));
      expect(h.view.phase, ConnectionPhase.disconnected);
    });

    test('superseded：准备期间被新意图取代，旧意图立刻终结且不会发送', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.intent(2, _off);
      expect(h.outcomes[1], [const RequestSuperseded()]);
      h.prepared(1); // 迟到的旧准备结果被丢弃
      expect(h.sends.map((s) => s.request.desired), [_off], reason: '不发送 on');
      expect(h.sends.single.id, 2);
    });

    test('superseded：已发送的旧请求被更新的请求取代（appliedSeq 超过它）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.intent(2, _off);
      expect(h.outcomes[1], isNull, reason: '新请求尚未被受理');
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 2,
          status: _stopping,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 2,
        ),
      );
      expect(h.outcomes[1], [const RequestSuperseded()]);
      expect(h.outcomes[2], isNull);
      h.snap(
        _s(
          version: 3,
          status: _stopped,
          attempt: 1,
          source: DesiredSource.app,
          appliedSeq: 2,
        ),
      );
      expect(h.outcomes[2], [const RequestSucceeded()]);
    });

    test('superseded：on 请求被受理后被外部入口（磁贴）置 off 覆盖', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(
        _s(
          version: 2,
          status: _stopping,
          attempt: 1,
          source: DesiredSource.tile,
          appliedSeq: 1,
        ),
      );
      expect(h.outcomes[1], [const RequestSuperseded()]);
    });

    test('failed：非最新请求的 RPC 失败仍是 failed（更新的请求尚未被受理），不展示失败', () {
      // disconnect 正在 RPC 中，新的 connect 还在准备；旧 disconnect 的 RPC 失败。
      final h = _connected();
      h.intent(2, _off);
      expect(h.sends.last.id, 2);
      h.intent(3, _on);
      h.sendFailed(2, const PlatformFailure('timeout', ''));
      expect(h.outcomes[2], [
        const RequestFailed(PlatformFailure('timeout', '')),
      ]);
      expect(h.view.failure, isNull, reason: '展示按最新意图：新的 connect 仍未确认');
      expect(h.view.phase, ConnectionPhase.connecting);
      // 新 connect 随后准备失败：只展示它自己的失败。
      h.prepareFailed(3, const NoActiveProfile());
      expect(h.outcomes[3], [const RequestFailed(NoActiveProfile())]);
      expect(h.view.failure, const NoActiveProfile());
    });

    test('superseded：非最新请求 RPC 失败、且更新的请求已被受理 → superseded', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      h.intent(2, _off);
      expect(h.sends.map((s) => s.id), [1, 2]);
      h.receipt(2, MachineHarness.accepted(2));
      h.sendFailed(1, const PlatformFailure('timeout', ''));
      expect(h.outcomes[1], [const RequestSuperseded()]);
      expect(h.view.failure, isNull);
    });

    test('非最新请求的 wrongEpoch 回执 → interrupted（纪元已变，不能再被确认）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      h.intent(2, _off);
      h.receipt(
        1,
        MachineHarness.rejected(RequestRejection.wrongEpoch, epoch: 'e2'),
      );
      expect(h.outcomes[1], [const RequestInterrupted()]);
    });

    test('interrupted：纪元变化时已发送、未终结的请求被中断，并重置基线', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(1, MachineHarness.accepted(1));
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 0));
      expect(h.outcomes[1], [const RequestInterrupted()]);
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.epoch, 'e2');
    });

    test('interrupted 之后迟到的回执/失败被忽略（每个意图只有一个结果）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.snap(_s(epoch: 'e2', version: 1));
      h.receipt(
        1,
        MachineHarness.rejected(RequestRejection.wrongEpoch, epoch: 'e2'),
      );
      h.sendFailed(1, const PlatformFailure('x', ''));
      expect(h.outcomes[1], [const RequestInterrupted()]);
    });

    test('纪元变化时尚未发送的最新意图保留，并在新纪元用新基线发送', () {
      final h = MachineHarness()..snap(_s(appliedSeq: 3));
      h.intent(1, _on);
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 10));
      expect(h.outcomes[1], isNull);
      h.prepared(1);
      expect(h.sends.single.request.epoch, 'e2');
      expect(h.sends.single.request.seq, 11);
    });

    test('每个意图的结果恰好一个（连发 on/off/on）', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.intent(2, _off);
      h.intent(3, _on);
      h.prepared(3);
      h.receipt(2, MachineHarness.accepted(1));
      h.receipt(3, MachineHarness.accepted(2));
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
        ),
      );
      expect(h.outcomes[1], [const RequestSuperseded()]);
      expect(h.outcomes[2], [const RequestSuperseded()]);
      expect(h.outcomes[3], [const RequestSucceeded()]);
    });
  });

  group('纪元变化重置', () {
    test('startedAt、attached、本地失败、基线全部重置', () {
      final h = _connected();
      expect(h.view.startedAt, isNotNull);
      h.snap(
        _s(
          epoch: 'e2',
          version: 1,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 0,
          rev: 1,
        ),
      );
      expect(h.view.startedAt, isNull, reason: '新纪元的首个快照即 started：attached');
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.view.epoch, 'e2');
    });

    test('新纪元后 seq 从新基线开始', () {
      final h = _connected();
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 40));
      h.intent(5, _on);
      h.prepared(5);
      expect(h.sends.last.request.seq, 41);
      expect(h.sends.last.request.epoch, 'e2');
    });

    test('旧纪元的迟到快照不会把状态拉回（同 epoch 才比 version；新纪元内旧 version 丢弃）', () {
      final h = _connected();
      h.snap(_s(epoch: 'e2', version: 5, appliedSeq: 0));
      h.snap(
        _s(epoch: 'e2', version: 4, status: _started, attempt: 9, desired: _on),
      );
      expect(h.view.phase, ConnectionPhase.disconnected);
    });

    test('乱序旧版本快照被丢弃', () {
      final h = MachineHarness()
        ..snap(_s(version: 5, status: _started, attempt: 1, desired: _on));
      h.snap(_s(version: 3));
      h.snap(_s(version: 5));
      expect(h.view.phase, ConnectionPhase.connected);
    });
  });

  group('seq 基线与回执（spec §10.1）', () {
    test('首个快照的 appliedSeq + 1 为基线；之后每个请求递增', () {
      final h = MachineHarness()..snap(_s(appliedSeq: 7));
      h.intent(1, _off);
      h.receipt(1, MachineHarness.accepted(8));
      h.intent(2, _off);
      expect(h.sends.map((s) => s.request.seq), [8, 9]);
    });

    test('准备期间的意图不占 seq：被取代的 on 不消耗序号', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.intent(2, _off);
      expect(h.sends.map((s) => s.request.seq), [1]);
    });

    test('快照显示 appliedSeq 超前（别的发送方）→ 基线上调', () {
      final h = MachineHarness()..snap(_s());
      h.snap(_s(version: 2, appliedSeq: 20));
      h.intent(1, _off);
      expect(h.sends.single.request.seq, 21);
    });

    test('stale 回执：以回执 appliedSeq + 1 重设基线，用新 seq 重发最新意图', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      expect(h.sends.single.request.seq, 1);
      h.receipt(
        1,
        MachineHarness.rejected(RequestRejection.stale, appliedSeq: 9),
      );
      expect(h.sends.map((s) => s.request.seq), [1, 10]);
      expect(h.sends.last.id, 1);
      expect(h.outcomes[1], isNull);
      expect(h.view.phase, ConnectionPhase.connecting);
    });

    test('wrongEpoch 回执：先重新同步，等新纪元快照到达后重发最新意图', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _on);
      h.prepared(1);
      h.receipt(
        1,
        MachineHarness.rejected(
          RequestRejection.wrongEpoch,
          epoch: 'e2',
          appliedSeq: 6,
        ),
      );
      expect(h.lastActions.whereType<Resync>(), hasLength(1));
      expect(h.sends, hasLength(1), reason: '新纪元快照到达前不重发');
      expect(h.outcomes[1], isNull);
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 6), fromResync: true);
      expect(h.sends, hasLength(2));
      expect(h.sends.last.request.epoch, 'e2');
      expect(h.sends.last.request.seq, 7);
      expect(h.outcomes[1], isNull, reason: 'wrongEpoch 的请求不算被纪元变化中断，意图继续');
    });

    test('stale/wrongEpoch 重发有上限，之后失败而不是无限循环', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      for (var i = 0; i <= ConnectionTiming.maxResends; i++) {
        h.receipt(
          1,
          MachineHarness.rejected(
            RequestRejection.stale,
            appliedSeq: 10 * (i + 1),
          ),
        );
      }
      expect(h.sends, hasLength(ConnectionTiming.maxResends + 1));
      expect(h.outcomes[1], hasLength(1));
      expect(h.outcomes[1]!.single, isA<RequestFailed>());
      expect(h.view.failure, isA<PlatformFailure>());
    });
  });

  group('未确认请求与失联（spec §5、§10.8）', () {
    test('请求受理后 5 s 内 appliedSeq 未追上 → 重新同步；快照追上则无失败', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      h.receipt(1, MachineHarness.accepted(1));
      h.advance(const Duration(milliseconds: 4999));
      expect(h.resyncs, 0);
      h.advance(const Duration(milliseconds: 1));
      expect(h.resyncs, 1);
      // 重新同步取回追上的快照：确认，无失败。
      h.snap(
        _s(version: 2, source: DesiredSource.app, appliedSeq: 1),
        fromResync: true,
      );
      expect(h.outcomes[1], [const RequestSucceeded()]);
      expect(h.view.failure, isNull);
      h.advance(const Duration(seconds: 30));
      expect(h.resyncs, 1);
      expect(h.view.failure, isNull);
    });

    test('重新同步后仍未追上 → nativeUnresponsive：请求 failed、phase 按快照、按钮可重发', () {
      final h = _connected();
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      h.advance(ConnectionTiming.unconfirmedRequestTimeout);
      expect(h.resyncs, 1);
      // 重新同步取回的仍是旧快照（版本相同，被过滤，但同步已完成）。
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
        fromResync: true,
      );
      expect(h.outcomes[2], [const RequestFailed(NativeUnresponsive())]);
      expect(h.view.failure, const NativeUnresponsive());
      expect(h.view.phase, ConnectionPhase.connected, reason: 'phase 按快照显示');
      expect(h.view.failureSeq, 1);
      // 点击 = 立即重新同步，**有效的重同步快照到达后**才为最新意图分配 seq 并发送。
      final before = h.resyncs;
      final sendsBefore = h.sends.length;
      h.intent(3, _off);
      expect(h.resyncs, before + 1);
      expect(h.sends.length, sendsBefore, reason: '重同步结果到达前不发送');
      expect(h.view.failure, isNull);
      expect(h.view.phase, ConnectionPhase.disconnecting);
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 2,
          rev: 1,
        ),
        fromResync: true,
      );
      expect(h.sends.length, sendsBefore + 1);
      expect(h.sends.last.id, 3);
      expect(h.sends.last.request.seq, 3, reason: '按重同步的新基线分配');
    });

    test('重新同步本身失败 / 无响应：宽限期后同样判 nativeUnresponsive', () {
      final h = _connected();
      h.intent(2, _off);
      h.receipt(2, MachineHarness.accepted(2));
      h.advance(ConnectionTiming.unconfirmedRequestTimeout);
      h.resyncFailed();
      expect(h.outcomes[2], [const RequestFailed(NativeUnresponsive())]);

      final g = _connected();
      g.intent(2, _off);
      g.receipt(2, MachineHarness.accepted(2));
      g.advance(ConnectionTiming.unconfirmedRequestTimeout);
      g.advance(ConnectionTiming.resyncGrace - const Duration(milliseconds: 1));
      expect(g.outcomes[2], isNull);
      g.advance(const Duration(milliseconds: 1));
      expect(g.outcomes[2], [const RequestFailed(NativeUnresponsive())]);
    });

    test('request() 回执迟迟不回：同样受 5 s + 重新同步 + 宽限约束', () {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      h.advance(ConnectionTiming.unconfirmedRequestTimeout);
      expect(h.resyncs, 1);
      h.resyncFailed();
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
    });

    test('nextWake 指向最近的截止时间', () {
      final h = MachineHarness()..snap(_s());
      expect(h.last.nextWake, isNull, reason: '空闲时无需唤醒');
      h.intent(1, _off);
      h.receipt(1, MachineHarness.accepted(1));
      expect(
        h.last.nextWake,
        h.now.add(ConnectionTiming.unconfirmedRequestTimeout),
      );
      final t0 = h.now;
      h.advance(ConnectionTiming.unconfirmedRequestTimeout);
      expect(
        h.last.nextWake,
        t0.add(
          ConnectionTiming.unconfirmedRequestTimeout +
              ConnectionTiming.resyncGrace,
        ),
      );
    });

    test('失联 10 s：phase 保持最后值 + stale + failure=nativeUnresponsive', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.advance(const Duration(milliseconds: 9999));
      expect(h.view.failure, isNull);
      expect(h.view.stale, isTrue);
      h.advance(const Duration(milliseconds: 1));
      expect(h.view.failure, const NativeUnresponsive());
      expect(h.view.phase, ConnectionPhase.connected);
      expect(h.view.stale, isTrue);
      expect(h.view.failureSeq, 1);
    });

    test('失联 10 s 后在途请求终结为 failed(nativeUnresponsive)，且各只一次', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.intent(2, _off);
      h.prepared(2);
      h.advance(const Duration(seconds: 10));
      expect(h.outcomes[2], [const RequestFailed(NativeUnresponsive())]);
      h.advance(const Duration(seconds: 30));
      expect(h.outcomes[2], hasLength(1));
      expect(h.view.failureSeq, 1);
    });

    test('失联恢复：failure 与 stale 一并清除', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.advance(const Duration(seconds: 10));
      expect(h.view.failure, const NativeUnresponsive());
      h.link(KernelLink.connected);
      expect(h.view.failure, isNull);
      expect(h.view.stale, isFalse);
      h.advance(const Duration(seconds: 30));
      expect(h.view.failure, isNull);
    });

    test('失联超时期间用户点击：立即重新同步并重新计 10 s 宽限', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.advance(const Duration(seconds: 10));
      expect(h.view.failure, const NativeUnresponsive());
      final before = h.resyncs;
      final sendsBefore = h.sends.length;
      h.intent(2, _off);
      expect(h.resyncs, before + 1);
      expect(h.view.failure, isNull);
      expect(h.sends.length, sendsBefore, reason: '重同步结果到达前不发送');
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
        fromResync: true,
      );
      expect(h.sends.last.id, 2);
      h.receipt(2, MachineHarness.accepted(2));
      h.snap(
        _s(version: 3, source: DesiredSource.app, attempt: 1, appliedSeq: 2),
      );
      expect(h.outcomes[2], [const RequestSucceeded()]);
      h.advance(const Duration(seconds: 9));
      expect(h.view.failure, isNull, reason: '宽限重新计时，没有立刻再次判失联');
      h.advance(const Duration(seconds: 1));
      expect(h.view.failure, const NativeUnresponsive());
      expect(h.view.failureSeq, 2, reason: '再次失联是新的失败');
    });

    test('从未收到首个快照：10 s 后 nativeUnresponsive，resolving 期间记录的意图也终结', () {
      final h = MachineHarness();
      h.intent(1, _on);
      h.prepared(1);
      h.advance(const Duration(milliseconds: 9999));
      expect(h.view.failure, isNull);
      h.advance(const Duration(milliseconds: 1));
      expect(h.view.phase, ConnectionPhase.resolving);
      expect(h.view.failure, const NativeUnresponsive());
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      // 之后首个快照到来恢复。
      h.snap(_s());
      expect(h.view.phase, ConnectionPhase.disconnected);
      expect(h.view.failure, isNull);
    });

    test('首次链路 lost（端口启动即报）也走 10 s 判定', () {
      final h = MachineHarness();
      h.link(KernelLink.lost);
      h.advance(const Duration(seconds: 10));
      expect(h.view.failure, const NativeUnresponsive());
    });
  });

  group('失联之后先重同步再发送（spec §10.8）', () {
    test('链路 lost 期间点击：只发 Resync，不发 SendRequest；重同步快照到达后才发送', () {
      final h = _connected();
      h.link(KernelLink.lost);
      final sendsBefore = h.sends.length;
      h.intent(2, _off);
      expect(h.lastActions.whereType<Resync>(), hasLength(1));
      expect(h.lastActions.whereType<SendRequest>(), isEmpty);
      expect(h.sends.length, sendsBefore);
      expect(h.state.awaitingResync, isTrue);
      expect(h.view.phase, ConnectionPhase.disconnecting);
      // watch 推来的普通快照不算重同步结果。
      h.snap(
        _s(
          version: 3,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
      );
      expect(h.sends.length, sendsBefore);
      h.snap(
        _s(
          version: 4,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 5,
          rev: 1,
        ),
        fromResync: true,
      );
      expect(h.state.awaitingResync, isFalse);
      expect(h.sends.length, sendsBefore + 1);
      expect(h.sends.last.id, 2);
      expect(h.sends.last.request.seq, 6, reason: '基线 = 重同步快照 appliedSeq + 1');
    });

    test('失联后点击，重同步返回新纪元：意图不被中断，按新纪元基线发送', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.intent(2, _off);
      expect(h.lastActions.whereType<SendRequest>(), isEmpty);
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 0), fromResync: true);
      expect(h.outcomes[2], isNull, reason: '从未发出的意图不会因纪元变化中断');
      expect(h.sends.last.id, 2);
      expect(h.sends.last.request.epoch, 'e2');
      expect(h.sends.last.request.seq, 1);
      h.receipt(2, MachineHarness.accepted(1, epoch: 'e2'));
      h.snap(
        _s(epoch: 'e2', version: 2, source: DesiredSource.app, appliedSeq: 1),
      );
      expect(h.outcomes[2], [const RequestSucceeded()]);
    });

    test('on 意图同样等待：准备完成后先重同步，结果到达后才置脏标记并发送', () {
      final h = MachineHarness()..snap(_s());
      h.link(KernelLink.lost);
      h.intent(1, _on);
      h.prepared(1);
      expect(h.lastActions.whereType<Resync>(), hasLength(1));
      expect(h.effectsOf(SideEffectKind.markSystemProxyDirty), isEmpty);
      expect(h.sends, isEmpty);
      h.snap(_s(version: 1), fromResync: true);
      expect(h.sends, hasLength(1));
      expect(h.effectsOf(SideEffectKind.markSystemProxyDirty), hasLength(1));
    });

    test('重同步失败：有界重试，仍失败则 failed(nativeUnresponsive)', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.intent(2, _off);
      expect(h.resyncs, 1);
      h.resyncFailed();
      expect(h.outcomes[2], isNull);
      expect(h.last.nextWake, isNotNull);
      for (var i = 1; i < ConnectionTiming.maxResyncAttempts; i++) {
        h.advance(ConnectionTiming.resyncRetryDelay);
        expect(h.resyncs, 1 + i);
        h.resyncFailed();
      }
      expect(h.outcomes[2], [const RequestFailed(NativeUnresponsive())]);
      expect(h.sends.where((s) => s.id == 2), isEmpty);
      expect(h.view.failure, const NativeUnresponsive());
    });

    test('链路恢复不等于重同步：恢复后点击仍先 Resync', () {
      final h = _connected();
      h.link(KernelLink.lost);
      h.link(KernelLink.connected);
      h.intent(2, _off);
      expect(h.lastActions.whereType<Resync>(), hasLength(1));
      expect(h.lastActions.whereType<SendRequest>(), isEmpty);
      h.snap(
        _s(
          version: 2,
          status: _started,
          attempt: 1,
          desired: _on,
          source: DesiredSource.app,
          appliedSeq: 1,
          rev: 1,
        ),
        fromResync: true,
      );
      expect(h.sends.last.id, 2);
      // 屏障已解除：下一次点击直接发送。
      h.intent(3, _on);
      h.prepared(3);
      expect(h.lastActions.whereType<SendRequest>(), hasLength(1));
      expect(h.lastActions.whereType<Resync>(), isEmpty);
    });
  });

  group('wrongEpoch 请求的独立截止时间（spec §10.1、§10.6）', () {
    MachineHarness wrongEpoch() {
      final h = MachineHarness()..snap(_s());
      h.intent(1, _off);
      h.receipt(
        1,
        MachineHarness.rejected(
          RequestRejection.wrongEpoch,
          epoch: 'e2',
          appliedSeq: 6,
        ),
      );
      return h;
    }

    test('等待新纪元期间 nextWake 不为空（不会无人唤醒）', () {
      final h = wrongEpoch();
      expect(h.resyncs, 1);
      expect(h.state.awaitingResync, isTrue);
      expect(h.last.nextWake, isNotNull);
    });

    test('重同步失败：有界重试后 failed', () {
      final h = wrongEpoch();
      for (var guard = 0; guard < 50 && h.outcomes[1] == null; guard++) {
        if (h.lastActions.whereType<Resync>().isNotEmpty) {
          h.resyncFailed();
        } else {
          h.now = h.last.nextWake!;
          h.feed(Tick(now: h.now));
        }
      }
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(h.resyncs, ConnectionTiming.maxResyncAttempts);
      expect(h.sends, hasLength(1), reason: '始终没有重发');
    });

    test('重同步只取回旧纪元快照：不算放行，有界重试后 failed', () {
      final h = wrongEpoch();
      var v = 1;
      for (var guard = 0; guard < 50 && h.outcomes[1] == null; guard++) {
        if (h.lastActions.whereType<Resync>().isNotEmpty) {
          h.snap(_s(version: ++v), fromResync: true);
        } else {
          h.now = h.last.nextWake!;
          h.feed(Tick(now: h.now));
        }
      }
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(h.sends, hasLength(1));
    });

    test('重同步一直不返回：独立截止时间到期 failed', () {
      final h = wrongEpoch();
      final t0 = h.now;
      while (h.outcomes[1] == null) {
        final wake = h.last.nextWake;
        expect(wake, isNotNull, reason: '等待中必须有唤醒时间');
        h.now = wake!;
        h.feed(Tick(now: h.now));
        expect(
          h.now.difference(t0),
          lessThanOrEqualTo(ConnectionTiming.resyncWaitTimeout),
        );
      }
      expect(h.outcomes[1], [const RequestFailed(NativeUnresponsive())]);
      expect(h.now.difference(t0), ConnectionTiming.resyncWaitTimeout);
    });

    test('第一次重同步失败、重试取回新纪元：按新基线重发并正常完成', () {
      final h = wrongEpoch();
      h.resyncFailed();
      h.advance(ConnectionTiming.resyncRetryDelay);
      expect(h.resyncs, 2);
      h.snap(_s(epoch: 'e2', version: 1, appliedSeq: 6), fromResync: true);
      expect(h.sends.last.request.epoch, 'e2');
      expect(h.sends.last.request.seq, 7);
      h.receipt(1, MachineHarness.accepted(7, epoch: 'e2'));
      h.snap(
        _s(epoch: 'e2', version: 2, source: DesiredSource.app, appliedSeq: 7),
      );
      expect(h.outcomes[1], [const RequestSucceeded()]);
    });
  });

  group('动作的值语义', () {
    test('相同字段的动作相等，toString 含全部字段', () {
      final a = SendRequest(
        1,
        DesiredRequest(
          epoch: 'e1',
          seq: 2,
          desired: _on,
          reason: RequestReason.userConnect,
          launch: MachineHarness.launch(3),
        ),
      );
      final b = SendRequest(
        1,
        DesiredRequest(
          epoch: 'e1',
          seq: 2,
          desired: _on,
          reason: RequestReason.userConnect,
          launch: MachineHarness.launch(3),
        ),
      );
      final c = SendRequest(
        1,
        DesiredRequest(
          epoch: 'e1',
          seq: 3,
          desired: _on,
          reason: RequestReason.userConnect,
          launch: MachineHarness.launch(3),
        ),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), isNot(c.toString()));
      expect(a.toString(), contains('seq=2'));
      expect(a.toString(), contains('rev=3'));
      expect(
        const SettleRequest(1, RequestFailed(StartTimeout())),
        isNot(const SettleRequest(1, RequestSuperseded())),
      );
      expect(
        const SettleRequest(1, RequestFailed(StartTimeout())).toString(),
        contains('StartTimeout'),
      );
      expect(
        const RunEffect(
          SideEffect(
            SideEffectKind.reportFailure,
            epoch: 'e1',
            attempt: 1,
            failure: KernelUnresponsive(),
          ),
        ).toString(),
        contains('KernelUnresponsive'),
      );
      expect(const Resync(), const Resync());
      expect(
        const PrepareLaunch(1, RequestReason.userConnect),
        isNot(const PrepareLaunch(2, RequestReason.userConnect)),
      );
    });
  });
}
