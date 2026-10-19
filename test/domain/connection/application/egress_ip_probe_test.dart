import 'dart:async';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_probe.dart';
import 'package:clashmiao/domain/connection/application/egress_ip_service.dart';
import 'package:clashmiao/domain/connection/model/connection_phase.dart';
import 'package:clashmiao/domain/connection/model/connection_snapshot.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_connection_controller.dart';

const _ok = EgressIpResult(ip: '203.0.113.7', countryCode: 'JP');
const _fail = EgressIpResult.unknown();

/// 脚本化的查询：按调用顺序返回 [results]（可带延迟）；记录调用时间。
class _Script {
  _Script(this.fa, this.results);

  final FakeAsync fa;
  final List<FutureOr<EgressIpResult> Function()> results;
  final List<Duration> callTimes = [];

  Future<EgressIpResult> call() async {
    callTimes.add(fa.elapsed);
    final i = callTimes.length - 1;
    final r = results[i < results.length ? i : results.length - 1];
    return await r();
  }
}

ConnectionSnapshot _conn({
  ConnectionPhase phase = ConnectionPhase.connected,
  String epoch = 'e1',
  int attempt = 1,
  bool replayPending = false,
}) => ConnectionSnapshot(
  phase: phase,
  epoch: epoch,
  attempt: attempt,
  replayPending: replayPending,
);

void _sim(
  String name,
  void Function(
    FakeAsync fa,
    ProviderContainer c,
    FakeConnectionController ctl,
    _Script script,
  )
  body, {
  required List<FutureOr<EgressIpResult> Function()> results,
  bool autoCheck = true,
  ConnectionSnapshot? initial,
}) {
  test(name, () async {
    SharedPreferences.setMockInitialValues({
      'clashmiao_auto_ip_check': autoCheck,
    });
    final prefs = await SharedPreferences.getInstance();
    fakeAsync((fa) {
      final script = _Script(fa, results);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          egressProbeFetchProvider.overrideWithValue(script.call),
          connectionControllerProvider.overrideWith(
            (ref) => FakeConnectionController(
              ref,
              snapshot: initial ?? ConnectionSnapshot.initial,
            ),
          ),
        ],
      );
      try {
        c.read(sharedPreferencesProvider);
        fa.flushMicrotasks();
        c.read(egressIpProbeProvider);
        fa.flushMicrotasks();
        body(
          fa,
          c,
          c.read(connectionControllerProvider.notifier)
              as FakeConnectionController,
          script,
        );
      } finally {
        c.dispose();
        fa.flushMicrotasks();
      }
    });
  });
}

EgressIpState _state(ProviderContainer c) => c.read(egressIpProbeProvider);

void main() {
  group('EgressIpProbe 触发', () {
    _sim('未连接：不查询，状态 notConnected', (fa, c, ctl, s) {
      ctl.set(_conn(phase: ConnectionPhase.disconnected));
      fa.elapse(const Duration(seconds: 30));

      expect(s.callTimes, isEmpty);
      expect(_state(c), EgressIpState.notConnected);
    }, results: [() => _ok]);

    _sim('已连接但手选重放未确认：等待；确认后才查询（首次就是正确的出口）', (fa, c, ctl, s) {
      ctl.set(_conn(replayPending: true));
      fa.elapse(const Duration(seconds: 5));
      expect(s.callTimes, isEmpty, reason: '重放没确认前走的还是默认节点，查到的 IP 会错');
      expect(_state(c).status, EgressIpStatus.idle);

      ctl.set(_conn(replayPending: false));
      fa.flushMicrotasks();

      expect(s.callTimes, hasLength(1));
      expect(_state(c), const EgressIpState(EgressIpStatus.success, _ok));
    }, results: [() => _ok]);

    _sim('同一个 (epoch, attempt) 只自动查一次，即使连接快照反复更新', (fa, c, ctl, s) {
      ctl.set(_conn());
      fa.flushMicrotasks();
      ctl.set(_conn().copyWithStartedAt());
      ctl.set(_conn());
      fa.elapse(const Duration(seconds: 5));

      expect(s.callTimes, hasLength(1));
    }, results: [() => _ok]);

    _sim(
      '自动检测关闭：已连接停在 idle（点击检测），不自动查询',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.elapse(const Duration(seconds: 5));

        expect(s.callTimes, isEmpty);
        expect(_state(c).status, EgressIpStatus.idle);
      },
      results: [() => _ok],
      autoCheck: false,
    );

    _sim(
      '冷启动就已连接且重放无需确认：立即查询',
      (fa, c, ctl, s) {
        fa.flushMicrotasks();
        expect(s.callTimes, hasLength(1));
      },
      results: [() => _ok],
      initial: _conn(),
    );
  });

  group('EgressIpProbe 节奏：串行最多 4 次、单次 4 s、间隔 1 s、首次成功即停', () {
    _sim('第 3 次成功：共 3 次调用，间隔 1 s，之后不再查', (fa, c, ctl, s) {
      ctl.set(_conn());
      fa.elapse(const Duration(seconds: 10));

      expect(s.callTimes, [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
      expect(_state(c), const EgressIpState(EgressIpStatus.success, _ok));
    }, results: [() => _fail, () => _fail, () => _ok]);

    _sim('4 次全失败：状态 failed，不再继续（失败后不死循环）', (fa, c, ctl, s) {
      ctl.set(_conn());
      fa.elapse(const Duration(seconds: 60));

      expect(s.callTimes, hasLength(4));
      expect(_state(c).status, EgressIpStatus.failed);
    }, results: [() => _fail]);

    _sim(
      '单次超时 4 s 的探测串行：第二次在第一次结束 + 1 s 之后才开始',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.elapse(const Duration(seconds: 30));

        expect(s.callTimes, [
          Duration.zero,
          const Duration(seconds: 5),
          const Duration(seconds: 10),
          const Duration(seconds: 15),
        ]);
        expect(_state(c).status, EgressIpStatus.failed);
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          EgressProbeTiming.perAttemptTimeout,
          () => _fail,
        ),
      ],
    );

    _sim(
      '查询中状态是 checking（不是未知 IP）',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.elapse(const Duration(milliseconds: 100));

        expect(_state(c).status, EgressIpStatus.checking);
        expect(_state(c).result, isNull);
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          const Duration(seconds: 3),
          () => _ok,
        ),
      ],
    );

    _sim('查询抛异常按失败处理，不让探测器崩', (fa, c, ctl, s) {
      ctl.set(_conn());
      fa.elapse(const Duration(seconds: 60));

      expect(_state(c).status, EgressIpStatus.failed);
    }, results: [() => throw StateError('boom')]);
  });

  group('EgressIpProbe 作废：(epoch, attempt) 变化 / 离开 connected / 手动查询', () {
    _sim(
      'attempt 变化（重载）：旧探测的迟到结果被丢弃，新 attempt 重新查',
      (fa, c, ctl, s) {
        ctl.set(_conn(attempt: 1));
        fa.elapse(const Duration(seconds: 1));
        expect(s.callTimes, hasLength(1), reason: '第一次查询还悬着');

        ctl.set(_conn(attempt: 2));
        fa.flushMicrotasks();
        expect(s.callTimes, hasLength(2), reason: '新 attempt 立即开始自己的探测');

        fa.elapse(const Duration(seconds: 30)); // 旧查询此时才 resolve
        expect(_state(c), const EgressIpState(EgressIpStatus.success, _fresh));
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          const Duration(seconds: 10),
          () => _stale,
        ),
        () => _fresh,
      ],
    );

    _sim(
      '纪元变化（原生进程重启）同样作废',
      (fa, c, ctl, s) {
        ctl.set(_conn(epoch: 'e1'));
        fa.elapse(const Duration(seconds: 1));
        ctl.set(_conn(epoch: 'e2'));
        fa.elapse(const Duration(seconds: 30));

        expect(_state(c), const EgressIpState(EgressIpStatus.success, _fresh));
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          const Duration(seconds: 10),
          () => _stale,
        ),
        () => _fresh,
      ],
    );

    _sim(
      '离开 connected：在途探测的结果被丢弃，状态回到 notConnected，不残留旧 IP',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.elapse(const Duration(seconds: 1));

        ctl.set(_conn(phase: ConnectionPhase.disconnected));
        fa.elapse(const Duration(seconds: 30));

        expect(_state(c), EgressIpState.notConnected);
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          const Duration(seconds: 10),
          () => _stale,
        ),
      ],
    );

    _sim('重载（reconnecting）期间不显示旧 IP', (fa, c, ctl, s) {
      ctl.set(_conn());
      fa.elapse(const Duration(seconds: 1));
      expect(_state(c).status, EgressIpStatus.success);

      ctl.set(_conn(phase: ConnectionPhase.reconnecting));
      fa.flushMicrotasks();

      expect(_state(c), EgressIpState.notConnected);
    }, results: [() => _fresh]);

    _sim(
      '手动查询使在途自动探测作废',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.elapse(const Duration(seconds: 1));
        expect(s.callTimes, hasLength(1));

        c.read(egressIpProbeProvider.notifier).checkNow();
        fa.flushMicrotasks();
        expect(s.callTimes, hasLength(2));

        fa.elapse(const Duration(seconds: 30));
        expect(_state(c), const EgressIpState(EgressIpStatus.success, _fresh));
      },
      results: [
        () => Future<EgressIpResult>.delayed(
          const Duration(seconds: 10),
          () => _stale,
        ),
        () => _fresh,
      ],
    );

    _sim(
      '自动检测关闭时点击检测：已连接才会查，失败后可再点重试',
      (fa, c, ctl, s) {
        ctl.set(_conn());
        fa.flushMicrotasks();
        expect(s.callTimes, isEmpty);

        c.read(egressIpProbeProvider.notifier).checkNow();
        fa.elapse(const Duration(seconds: 60));
        expect(_state(c).status, EgressIpStatus.failed);
        final firstRound = s.callTimes.length;

        c.read(egressIpProbeProvider.notifier).checkNow();
        fa.flushMicrotasks();
        expect(s.callTimes.length, firstRound + 1, reason: '失败后点击重试再来一轮');
      },
      results: [() => _fail],
      autoCheck: false,
    );

    _sim('未连接时手动查询无效', (fa, c, ctl, s) {
      ctl.set(_conn(phase: ConnectionPhase.disconnected));
      c.read(egressIpProbeProvider.notifier).checkNow();
      fa.elapse(const Duration(seconds: 5));

      expect(s.callTimes, isEmpty);
    }, results: [() => _ok]);
  });
}

const _stale = EgressIpResult(ip: '192.0.2.1', countryCode: 'CN');
const _fresh = EgressIpResult(ip: '198.51.100.2', countryCode: 'US');

extension on ConnectionSnapshot {
  /// 同一个 (epoch, attempt) 下别的字段变化（例如 startedAt）。
  ConnectionSnapshot copyWithStartedAt() => ConnectionSnapshot(
    phase: phase,
    epoch: epoch,
    attempt: attempt,
    replayPending: replayPending,
    startedAt: DateTime(2026),
  );
}
