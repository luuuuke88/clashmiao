import 'dart:math';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/domain/connection/application/connection_machine.dart';
import 'package:clashmiao/domain/connection/model/connection_failure.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/machine_harness.dart';

// 随机序列只验「安全性质」（P3）；「每个请求最终终结」由下半部分的脚本化 +
// 可控时钟测试覆盖。

final _t0 = DateTime.utc(2026, 1, 1, 12);

/// 由种子确定地生成一串事件（不依赖机器状态，除了读取机器已发出的 seq/id 范围
/// 以便让回执等事件大致「对得上」）。
List<MachineEvent> _generate(int seed, {int length = 60}) {
  final rnd = Random(seed);
  final events = <MachineEvent>[];
  var now = _t0;
  var epoch = 'e1';
  var version = 0;
  var attempt = 0;
  var applied = 0;
  var nextId = 1;
  var maxSeqGuess = 0;

  T pick<T>(List<T> xs) => xs[rnd.nextInt(xs.length)];

  for (var i = 0; i < length; i++) {
    now = now.add(
      Duration(
        milliseconds: rnd.nextInt(10) == 0
            ? 1000 + rnd.nextInt(12000)
            : rnd.nextInt(1500),
      ),
    );
    final r = rnd.nextInt(100);
    if (r < 38) {
      if (rnd.nextInt(12) == 0) {
        epoch = 'e${1 + rnd.nextInt(3)}';
        version = rnd.nextInt(3);
        applied = rnd.nextInt(5);
        attempt = rnd.nextInt(3);
      }
      version += rnd.nextInt(5) == 0 ? -rnd.nextInt(3) : 1;
      if (rnd.nextInt(3) == 0) attempt += 1;
      if (rnd.nextBool()) applied = max(applied, rnd.nextInt(maxSeqGuess + 3));
      final failureRoll = rnd.nextInt(10);
      events.add(
        SnapshotReceived(
          MachineHarness.snapshot(
            epoch: epoch,
            version: version,
            status: pick(KernelStatus.values),
            attempt: attempt,
            desired: pick(Desired.values),
            source: pick(DesiredSource.values),
            appliedSeq: applied,
            activeConfigRevision: rnd.nextBool() ? 1 + rnd.nextInt(3) : null,
            selectionsReplayNeeded: rnd.nextBool(),
            lastFailure: failureRoll < 3
                ? KernelFailure(
                    code: pick(KernelFailureCode.values),
                    message: 'm',
                    attempt: max(0, attempt - rnd.nextInt(2)),
                    seq: rnd.nextBool() ? rnd.nextInt(maxSeqGuess + 2) : null,
                  )
                : null,
          ),
          now: now,
          fromResync: rnd.nextInt(6) == 0,
        ),
      );
    } else if (r < 46) {
      events.add(LinkChanged(pick(KernelLink.values), now: now));
    } else if (r < 58) {
      events.add(Tick(now: now));
    } else if (r < 72) {
      final desired = pick(Desired.values);
      events.add(
        UserIntent(
          id: nextId++,
          desired: desired,
          reason: pick(RequestReason.values),
          now: now,
        ),
      );
    } else if (r < 80) {
      final id = 1 + rnd.nextInt(max(1, nextId));
      events.add(
        rnd.nextInt(4) == 0
            ? LaunchPrepareFailed(
                id: id,
                failure: const ConfigMissing(),
                now: now,
              )
            : LaunchPrepared(
                id: id,
                launch: MachineHarness.launch(1 + rnd.nextInt(3)),
                now: now,
              ),
      );
    } else if (r < 92) {
      maxSeqGuess += 1;
      final id = 1 + rnd.nextInt(max(1, nextId));
      final k = rnd.nextInt(5);
      events.add(
        ReceiptReceived(
          id: id,
          receipt: switch (k) {
            0 => MachineHarness.rejected(
              RequestRejection.stale,
              epoch: epoch,
              appliedSeq: applied + rnd.nextInt(4),
            ),
            1 => MachineHarness.rejected(
              RequestRejection.wrongEpoch,
              epoch: 'e${1 + rnd.nextInt(3)}',
              appliedSeq: rnd.nextInt(4),
            ),
            _ => MachineHarness.accepted(maxSeqGuess, epoch: epoch),
          },
          now: now,
        ),
      );
    } else if (r < 96) {
      events.add(
        SendFailed(
          id: 1 + rnd.nextInt(max(1, nextId)),
          failure: const PlatformFailure('x', ''),
          now: now,
        ),
      );
    } else {
      events.add(ResyncFailed(now: now));
    }
  }
  return events;
}

const _oncePerAttempt = {
  SideEffectKind.hapticHeavy,
  SideEffectKind.requestReview,
  SideEffectKind.hapticMedium,
  SideEffectKind.replaySelections,
  SideEffectKind.clearSystemProxyDirty,
};

void main() {
  group('随机快照/事件序列：安全性质（固定种子，500 条）', () {
    test('phase 由输入唯一确定；副作用每 (epoch,attempt) 至多一次；无矛盾动作', () {
      for (var seed = 0; seed < 500; seed++) {
        final events = _generate(seed);
        final ctx = 'seed=$seed';

        // 第一遍：检查性质；第二遍：同样输入必须得到完全相同的输出（确定性）。
        final firstViews = <String>[];
        final firstActions = <String>[];
        for (var pass = 0; pass < 2; pass++) {
          var state = MachineState.initial(_t0);
          final raised = <int>{};
          final settled = <int>{};
          final effectKeys = <EffectKey>{};
          final lastSeqByEpoch = <String, int>{};
          var failureSeq = 0;
          var sawSnapshot = false;

          for (final (i, e) in events.indexed) {
            final where = '$ctx step=$i ${e.runtimeType}';
            final t = const ConnectionMachine().reduce(state, e);
            state = t.state;
            final v = t.snapshot;
            if (e is UserIntent) raised.add(e.id);
            if (state.snapshot != null) sawSnapshot = true;

            if (pass == 0) {
              firstViews.add(v.toString());
              firstActions.add(t.actions.map((a) => a.toString()).join('|'));
            } else {
              expect(v.toString(), firstViews[i], reason: '$where 视图不确定');
              expect(
                t.actions.map((a) => a.toString()).join('|'),
                firstActions[i],
                reason: '$where 动作不确定',
              );
              continue;
            }

            // 终结：只对发起过的意图，且每个意图至多一次。
            for (final a in t.actions.whereType<SettleRequest>()) {
              expect(raised, contains(a.id), reason: '$where 终结了不存在的意图');
              expect(settled.add(a.id), isTrue, reason: '$where 重复终结 #${a.id}');
            }
            // 已终结的意图不能再被发送；未终结的意图仍在请求表里。
            final sends = t.actions.whereType<SendRequest>().toList();
            expect(sends.length, lessThanOrEqualTo(1), reason: where);
            for (final s in sends) {
              expect(settled, isNot(contains(s.id)), reason: '$where 发送了已终结意图');
              expect(sawSnapshot, isTrue, reason: '$where 无快照就发送');
              expect(s.request.epoch, state.snapshot!.epoch, reason: where);
              final last = lastSeqByEpoch[s.request.epoch];
              if (last != null) {
                expect(
                  s.request.seq,
                  greaterThan(last),
                  reason: '$where seq 回退',
                );
              }
              lastSeqByEpoch[s.request.epoch] = s.request.seq;
              expect(
                s.request.desired == Desired.on,
                s.request.launch != null,
                reason: '$where on 必带 launch，off 不带',
              );
            }
            for (final r in state.requests) {
              expect(settled, isNot(contains(r.id)), reason: '$where 已终结仍在表中');
            }
            // 请求表里每个意图都被引用过，且 id 唯一。
            expect(
              state.requests.map((r) => r.id).toSet().length,
              state.requests.length,
              reason: where,
            );
            // 只有最新意图可以是「未发送」。
            for (final r in state.requests.take(
              max(0, state.requests.length - 1),
            )) {
              expect(
                r.stage == RequestStage.inFlight ||
                    r.stage == RequestStage.awaiting,
                isTrue,
                reason: '$where 非最新意图必须已发送',
              );
            }

            // 副作用：每 (epoch, attempt, kind) 至多一次（epoch 变化后重置不影响，
            // 因为键含 epoch；同一 epoch 再次出现时集合已重置——所以只在同一
            // epoch 连续段内断言）。
            final effects = t.actions.whereType<RunEffect>().map(
              (a) => a.effect,
            );
            final kinds = effects.map((e) => e.kind).toList();
            expect(
              !(kinds.contains(SideEffectKind.hapticHeavy) &&
                  kinds.contains(SideEffectKind.hapticMedium)),
              isTrue,
              reason: '$where 同一快照既连接触觉又断开触觉',
            );
            expect(
              !(kinds.contains(SideEffectKind.markSystemProxyDirty) &&
                  kinds.contains(SideEffectKind.clearSystemProxyDirty)),
              isTrue,
              reason: '$where 同时置与清脏标记',
            );
            for (final ef in effects) {
              if (!_oncePerAttempt.contains(ef.kind)) continue;
              final key = (ef.epoch!, ef.attempt!, ef.kind);
              expect(effectKeys.add(key), isTrue, reason: '$where 副作用重复 $key');
            }
            // 纪元变化 → 去重集合重置（键含 epoch，离开的纪元不再约束）。
            effectKeys.removeWhere((k) => k.$1 != state.snapshot?.epoch);
            lastSeqByEpoch.removeWhere((k, _) => k != state.snapshot?.epoch);

            // 视图不变量。
            if (v.phase == ConnectionPhase.resolving) {
              expect(state.snapshot, isNull, reason: where);
              expect(v.startedAt, isNull, reason: where);
              expect(v.origin, isNull, reason: where);
            } else {
              expect(state.snapshot, isNotNull, reason: where);
              expect(v.epoch, state.snapshot!.epoch, reason: where);
            }
            if (v.phase == ConnectionPhase.disconnected) {
              expect(v.startedAt, isNull, reason: '$where 已断开不应有 startedAt');
              expect(v.isBusy, isFalse, reason: where);
            }
            expect(
              v.isBusy,
              v.phase != ConnectionPhase.connected &&
                  v.phase != ConnectionPhase.disconnected,
              reason: where,
            );
            expect(
              v.stale,
              state.snapshot != null && state.link == KernelLink.lost,
              reason: where,
            );
            expect(
              v.failureSeq,
              greaterThanOrEqualTo(failureSeq),
              reason: where,
            );
            expect(
              v.failureSeq - failureSeq,
              lessThanOrEqualTo(1),
              reason: where,
            );
            failureSeq = v.failureSeq;
            final snap = state.snapshot;
            if (snap != null &&
                state.requests.any(
                  (r) => r.seq == null || r.seq! > snap.appliedSeq,
                )) {
              expect(v.failure, isNull, reason: '$where 有未确认请求时不展示失败');
            }

            // 唤醒时间必须在将来（到期的截止时间已在本次处理掉）。
            final wake = t.nextWake;
            if (wake != null) {
              expect(
                wake.isAfter(e.now),
                isTrue,
                reason: '$where nextWake 不在将来',
              );
            }
          }
        }
      }
    });

    test('只有快照/链路的序列：phase 恰好是快照的纯函数（独立预言机）', () {
      for (var seed = 0; seed < 500; seed++) {
        final rnd = Random(seed);
        var state = MachineState.initial(_t0);
        var now = _t0;
        var version = 0;
        var established = false;
        KernelSnapshot? latest;
        for (var i = 0; i < 40; i++) {
          now = now.add(Duration(milliseconds: rnd.nextInt(800)));
          version++;
          final s = MachineHarness.snapshot(
            version: version,
            status: KernelStatus.values[rnd.nextInt(4)],
            attempt: rnd.nextInt(4),
            desired: Desired.values[rnd.nextInt(2)],
            source: DesiredSource.values[rnd.nextInt(6)],
            appliedSeq: rnd.nextInt(3),
          );
          final prev = latest;
          latest = s;
          final t = const ConnectionMachine().reduce(
            state,
            SnapshotReceived(s, now: now),
          );
          state = t.state;
          // 预言机：独立复述 spec §5（无本地请求、无失败）。
          if (s.status == KernelStatus.started && prev == null) {
            established = true;
          }
          if (s.status == KernelStatus.started &&
              s.desired == Desired.on &&
              prev != null &&
              !established) {
            established = true;
          }
          if (s.status == KernelStatus.stopped && s.desired == Desired.off) {
            established = false;
          }
          final expected = s.desired == Desired.on
              ? (s.status == KernelStatus.started
                    ? ConnectionPhase.connected
                    : (established
                          ? ConnectionPhase.reconnecting
                          : ConnectionPhase.connecting))
              : (s.status == KernelStatus.stopped
                    ? ConnectionPhase.disconnected
                    : ConnectionPhase.disconnecting);
          expect(t.snapshot.phase, expected, reason: 'seed=$seed step=$i $s');
        }
      }
    });
  });
}
