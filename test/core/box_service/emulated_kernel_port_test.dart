import 'dart:async';

import 'package:clashmiao/core/box_service/emulated_kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/model/box_alert.dart';
import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import '../../support/fake_box_service.dart';

/// 脚本化的平台服务：记录调用，状态推送由测试或各 behavior 决定。
class _ScriptedBox extends FakeBoxService {
  _ScriptedBox({BoxStatus initial = const BoxStopped()})
    : status = BehaviorSubject<BoxStatus>.seeded(initial);

  final BehaviorSubject<BoxStatus> status;
  final StreamController<BoxAlert> alerts = StreamController.broadcast();
  final List<String> calls = [];
  final List<String> options = [];

  /// 每个 behavior 默认模拟「平台正常推送」。
  late Future<void> Function(String path) startBehavior = (_) async {
    status.add(const BoxStarting());
    status.add(const BoxStarted());
  };
  late Future<void> Function() stopBehavior = () async {
    status.add(const BoxStopping());
    status.add(const BoxStopped());
  };
  late Future<void> Function(String path) restartBehavior = (_) async {
    status.add(const BoxStopping());
    status.add(const BoxStopped());
    status.add(const BoxStarting());
    status.add(const BoxStarted());
  };
  Future<void> Function(String group, String tag)? selectBehavior;

  @override
  Stream<BoxStatus> watchStatus() => status.stream;
  @override
  Stream<BoxAlert> watchAlerts() => alerts.stream;
  @override
  Future<void> changeConfigOptions(String jsonOptions) async =>
      options.add(jsonOptions);
  @override
  Future<void> start(String configPath, {String name = ''}) {
    calls.add('start:$configPath');
    return startBehavior(configPath);
  }

  @override
  Future<void> stop() {
    calls.add('stop');
    return stopBehavior();
  }

  @override
  Future<void> restart(String configPath, {String name = ''}) {
    calls.add('restart:$configPath');
    return restartBehavior(configPath);
  }

  @override
  Future<void> selectOutbound(String groupTag, String outboundTag) {
    calls.add('select:$groupTag/$outboundTag');
    return selectBehavior?.call(groupTag, outboundTag) ?? Future<void>.value();
  }

  Future<void> close() async {
    await status.close();
    await alerts.close();
  }
}

LaunchSpec _spec(int seq, {int rev = 1}) => LaunchSpec(
  runtimeConfigPath: '/rc/runtime-config-$seq.json',
  optionsJson: '{"rev":$rev}',
  profileName: 'p',
  configRevision: rev,
);

DesiredRequest _on(int seq, {int rev = 1, String epoch = 'ep'}) =>
    DesiredRequest(
      epoch: epoch,
      seq: seq,
      desired: Desired.on,
      reason: RequestReason.userConnect,
      launch: _spec(seq, rev: rev),
    );

DesiredRequest _off(int seq, {String epoch = 'ep'}) => DesiredRequest(
  epoch: epoch,
  seq: seq,
  desired: Desired.off,
  reason: RequestReason.userDisconnect,
);

EmulatedKernelPort _port(
  _ScriptedBox box, {
  Duration startTimeout = const Duration(seconds: 30),
  Duration stopTimeout = const Duration(seconds: 20),
}) => EmulatedKernelPort(
  box,
  epochGenerator: () => 'ep',
  startTimeout: startTimeout,
  stopTimeout: stopTimeout,
);

void main() {
  late _ScriptedBox box;
  late EmulatedKernelPort port;
  late List<KernelSnapshot> seen;
  late StreamSubscription<KernelSnapshot> sub;
  var initialized = false;

  setUp(() => initialized = false);

  Future<void> setUp0({
    BoxStatus initial = const BoxStopped(),
    Duration startTimeout = const Duration(seconds: 30),
    Duration stopTimeout = const Duration(seconds: 20),
  }) async {
    initialized = true;
    box = _ScriptedBox(initial: initial);
    port = _port(box, startTimeout: startTimeout, stopTimeout: stopTimeout);
    seen = [];
    sub = port.watch().listen(seen.add);
    await pumpEventQueue();
  }

  tearDown(() async {
    if (!initialized) return;
    await sub.cancel();
    await port.dispose();
    await box.close();
  });

  KernelSnapshot last() => seen.last;

  group('初始快照', () {
    test('平台已停止：stopped / desired off / source system / attempt 0', () async {
      await setUp0();
      expect(seen, hasLength(1));
      final s = seen.single;
      expect(s.epoch, 'ep');
      expect(s.version, 1);
      expect(s.status, KernelStatus.stopped);
      expect(s.desired, Desired.off);
      expect(s.source, DesiredSource.system);
      expect(s.attempt, 0);
      expect(s.appliedSeq, 0);
      expect(s.selectionsReplayNeeded, isFalse);
      expect(await port.current(), s);
    });

    test('冷启动挂上运行中的隧道（attached）：started / desired on / 不要求重放', () async {
      await setUp0(initial: const BoxStarted());
      final s = seen.single;
      expect(s.status, KernelStatus.started);
      expect(s.desired, Desired.on);
      expect(s.source, DesiredSource.system);
      expect(s.attempt, 0);
      expect(s.selectionsReplayNeeded, isFalse);
    });

    test('订阅晚于初始化时同样先收到当前值', () async {
      await setUp0();
      final late = <KernelSnapshot>[];
      final s2 = port.watch().listen(late.add);
      await pumpEventQueue();
      expect(late, [seen.single]);
      await s2.cancel();
    });
  });

  group('请求受理与收敛', () {
    test(
      'connect：desired on → starting(attempt 1) → started，带 revision 并要求重放',
      () async {
        await setUp0();
        final receipt = await port.request(_on(1, rev: 7));
        expect(
          receipt,
          const RequestReceipt(accepted: true, epoch: 'ep', appliedSeq: 1),
        );
        await pumpEventQueue();

        expect(box.options, ['{"rev":7}']);
        expect(box.calls, ['start:/rc/runtime-config-1.json']);
        final steps = seen
            .map((s) => '${s.status.name}/${s.desired.name}/${s.attempt}')
            .toList();
        expect(steps, [
          'stopped/off/0',
          'stopped/on/0', // 请求已受理，尚未开始执行
          'starting/on/1',
          'started/on/1',
        ]);
        final s = last();
        expect(s.source, DesiredSource.app);
        expect(s.appliedSeq, 1);
        expect(s.activeConfigRevision, 7);
        expect(s.selectionsReplayNeeded, isTrue);
        expect(s.lastFailure, isNull);
        // 版本严格递增
        for (var i = 1; i < seen.length; i++) {
          expect(seen[i].version, greaterThan(seen[i - 1].version));
        }
      },
    );

    test('on/off/on 同一事件循环内连发：只执行最后一个，内核只启动一次', () async {
      await setUp0();
      final r1 = port.request(_on(1));
      final r2 = port.request(_off(2));
      final r3 = port.request(_on(3, rev: 2));
      expect(
        (await Future.wait([r1, r2, r3])).every((r) => r.accepted),
        isTrue,
      );
      await pumpEventQueue();

      expect(box.calls, ['start:/rc/runtime-config-3.json']);
      expect(box.options, ['{"rev":2}']);
      expect(last().status, KernelStatus.started);
      expect(last().appliedSeq, 3);
      expect(last().activeConfigRevision, 2);
      expect(last().attempt, 1);
    });

    test('on 后紧跟 off：内核根本不启动', () async {
      await setUp0();
      final r1 = port.request(_on(1));
      final r2 = port.request(_off(2));
      await Future.wait([r1, r2]);
      await pumpEventQueue();
      expect(box.calls, isEmpty);
      expect(last().status, KernelStatus.stopped);
      expect(last().desired, Desired.off);
      expect(last().appliedSeq, 2);
      expect(last().lastFailure, isNull);
    });

    test('stale 序号被拒绝且不改变任何状态；wrongEpoch 同样', () async {
      await setUp0();
      await port.request(_on(5));
      await pumpEventQueue();
      final before = last();
      final count = seen.length;

      final same = await port.request(_off(5));
      final older = await port.request(_off(3));
      final wrong = await port.request(_off(9, epoch: 'other'));
      await pumpEventQueue();

      expect(same.accepted, isFalse);
      expect(same.reason, RequestRejection.stale);
      expect(same.appliedSeq, 5);
      expect(older.reason, RequestRejection.stale);
      expect(wrong.accepted, isFalse);
      expect(wrong.reason, RequestRejection.wrongEpoch);
      expect(wrong.epoch, 'ep');
      expect(seen, hasLength(count));
      expect(last(), before);
      expect(box.calls, hasLength(1)); // 只有最初那次 start
    });

    test('缺号不等待：seq 跳号照常受理', () async {
      await setUp0();
      expect((await port.request(_on(10))).accepted, isTrue);
      await pumpEventQueue();
      expect(last().appliedSeq, 10);
    });

    test('disconnect：stopping → stopped，不写 failure', () async {
      await setUp0();
      await port.request(_on(1));
      await pumpEventQueue();
      await port.request(_off(2));
      await pumpEventQueue();
      expect(box.calls.last, 'stop');
      expect(last().status, KernelStatus.stopped);
      expect(last().desired, Desired.off);
      expect(last().source, DesiredSource.app);
      expect(last().activeConfigRevision, isNull);
      expect(last().lastFailure, isNull);
      expect(
        seen.map((s) => s.status),
        containsAllInOrder([
          KernelStatus.started,
          KernelStatus.stopping,
          KernelStatus.stopped,
        ]),
      );
    });

    test('启动执行中收到 off：不并发，启动返回后完整回收', () async {
      await setUp0();
      final gate = Completer<void>();
      box.startBehavior = (_) async {
        box.status.add(const BoxStarting());
        await gate.future;
        box.status.add(const BoxStarted());
      };
      await port.request(_on(1));
      await pumpEventQueue();
      expect(last().status, KernelStatus.starting);

      await port.request(_off(2));
      await pumpEventQueue();
      // 阻塞调用未返回：状态如实，stop 还没发起。
      expect(box.calls, ['start:/rc/runtime-config-1.json']);
      expect(last().desired, Desired.off);
      expect(last().status, KernelStatus.starting);

      gate.complete();
      await pumpEventQueue();
      expect(box.calls, ['start:/rc/runtime-config-1.json', 'stop']);
      expect(last().status, KernelStatus.stopped);
      expect(last().desired, Desired.off);
      expect(last().lastFailure, isNull);
    });
  });

  group('失败归属', () {
    test('启动抛异常：desired 置 off、写 failure（attempt/seq），回收到 stopped', () async {
      await setUp0();
      box.startBehavior = (_) async {
        box.status.add(const BoxStarting());
        throw PlatformException(code: 'E_START', message: 'bad config');
      };
      await port.request(_on(4));
      await pumpEventQueue();

      final s = last();
      expect(s.status, KernelStatus.stopped);
      expect(s.desired, Desired.off);
      expect(s.appliedSeq, 4);
      expect(
        s.lastFailure,
        const KernelFailure(
          code: KernelFailureCode.startService,
          message: 'E_START: bad config',
          attempt: 1,
          seq: 4,
        ),
      );
      expect(box.calls, contains('stop'));
    });

    test('启动 30 s 超时（默认值）：failure=startTimeout，desired off，回收', () {
      fakeAsync((async) {
        final b = _ScriptedBox();
        final p = _port(b);
        final snaps = <KernelSnapshot>[];
        final s = p.watch().listen(snaps.add);
        b.startBehavior = (_) async {
          b.status.add(const BoxStarting());
          await Completer<void>().future; // 永不返回
        };
        async.flushMicrotasks();
        p.request(_on(1));
        async.flushMicrotasks();
        expect(snaps.last.status, KernelStatus.starting);

        async.elapse(const Duration(seconds: 29, milliseconds: 900));
        expect(snaps.last.status, KernelStatus.starting);
        expect(snaps.last.lastFailure, isNull);

        async.elapse(const Duration(milliseconds: 200));
        final f = snaps.last;
        expect(f.desired, Desired.off);
        expect(f.lastFailure?.code, KernelFailureCode.startTimeout);
        expect(f.lastFailure?.seq, 1);
        expect(f.lastFailure?.attempt, 1);
        expect(f.status, KernelStatus.stopped);
        expect(b.calls, contains('stop'));

        s.cancel();
        p.dispose();
        b.close();
        async.flushMicrotasks();
      });
    });

    test('fatal alert 在启动期间到达：映射失败码并回收', () async {
      await setUp0();
      final gate = Completer<void>();
      box.startBehavior = (_) async {
        box.status.add(const BoxStarting());
        await gate.future;
      };
      await port.request(_on(1));
      await pumpEventQueue();
      box.alerts.add(
        const BoxAlert(type: BoxAlertType.emptyConfiguration, message: 'empty'),
      );
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(last().lastFailure?.code, KernelFailureCode.emptyConfiguration);
      expect(last().lastFailure?.message, 'empty');
      expect(last().desired, Desired.off);
      expect(last().status, KernelStatus.stopped);
    });

    test('非 fatal alert 不影响启动', () async {
      await setUp0();
      box.alerts.add(const BoxAlert(type: BoxAlertType.requestVpnPermission));
      await port.request(_on(1));
      await pumpEventQueue();
      expect(last().status, KernelStatus.started);
      expect(last().lastFailure, isNull);
    });

    test('失败的执行已被更新请求取代：只回收，不改 desired、不写 failure', () async {
      await setUp0();
      final gate = Completer<void>();
      var first = true;
      box.startBehavior = (_) async {
        box.status.add(const BoxStarting());
        if (first) {
          first = false;
          await gate.future;
          throw StateError('old attempt dies');
        }
        box.status.add(const BoxStarted());
      };
      await port.request(_on(1));
      await pumpEventQueue();
      await port.request(_on(2, rev: 2));
      gate.complete();
      await pumpEventQueue();

      expect(box.calls.where((c) => c.startsWith('start')), hasLength(2));
      expect(last().lastFailure, isNull);
      expect(last().desired, Desired.on);
      expect(last().status, KernelStatus.started);
      expect(last().appliedSeq, 2);
      expect(last().activeConfigRevision, 2);
      expect(last().attempt, 2);
    });

    test('停止超 20 s：kernelUnresponsive，状态保持 stopping；新请求再次回收', () async {
      await setUp0(stopTimeout: const Duration(milliseconds: 50));
      await port.request(_on(1));
      await pumpEventQueue();
      box.stopBehavior = () async {}; // 平台永远不推 Stopped
      await port.request(_off(2));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(last().status, KernelStatus.stopping);
      expect(last().desired, Desired.off);
      expect(last().lastFailure?.code, KernelFailureCode.kernelUnresponsive);
      expect(last().lastFailure?.seq, 2);
      final stops = box.calls.where((c) => c == 'stop').length;
      expect(stops, 1, reason: '卡住后不自旋重试');

      // 平台恢复；按钮「重发 off」→ 再回收一次并到达 stopped
      box.stopBehavior = () async {
        box.status.add(const BoxStopped());
      };
      await port.request(_off(3));
      await pumpEventQueue();
      expect(box.calls.where((c) => c == 'stop'), hasLength(2));
      expect(last().status, KernelStatus.stopped);
    });

    test('核心库不可用（Stub）：on 请求立即 coreUnavailable，不调用内核', () async {
      const stub = StubBoxService(reason: StubReason.coreLoadFailed);
      final p = EmulatedKernelPort(stub, epochGenerator: () => 'ep');
      final snaps = <KernelSnapshot>[];
      final s = p.watch().listen(snaps.add);
      await pumpEventQueue();
      await p.request(_on(1));
      await pumpEventQueue();
      expect(snaps.last.desired, Desired.off);
      expect(snaps.last.status, KernelStatus.stopped);
      expect(snaps.last.attempt, 0);
      expect(snaps.last.lastFailure?.code, KernelFailureCode.coreUnavailable);
      expect(snaps.last.lastFailure?.seq, 1);
      await s.cancel();
      await p.dispose();
    });
  });

  group('配置重载', () {
    test('revision 变化触发 restart（attempt+1，重新要求重放）', () async {
      await setUp0();
      await port.request(_on(1, rev: 1));
      await pumpEventQueue();
      await port.acknowledgeReplay(1);
      await pumpEventQueue();
      expect(last().selectionsReplayNeeded, isFalse);

      await port.request(_on(2, rev: 2));
      await pumpEventQueue();
      expect(box.calls, [
        'start:/rc/runtime-config-1.json',
        'restart:/rc/runtime-config-2.json',
      ]);
      expect(box.options.last, '{"rev":2}');
      expect(last().status, KernelStatus.started);
      expect(last().attempt, 2);
      expect(last().activeConfigRevision, 2);
      expect(last().selectionsReplayNeeded, isTrue);
      expect(last().appliedSeq, 2);
    });

    test('相同 revision：不重启、attempt 不变，只推进 appliedSeq', () async {
      await setUp0();
      await port.request(_on(1, rev: 3));
      await pumpEventQueue();
      await port.request(_on(2, rev: 3));
      await pumpEventQueue();
      expect(box.calls, ['start:/rc/runtime-config-1.json']);
      expect(last().attempt, 1);
      expect(last().appliedSeq, 2);
      expect(last().status, KernelStatus.started);
    });

    test('重载失败：desired off、failure 归属该请求、回收到 stopped', () async {
      await setUp0();
      await port.request(_on(1, rev: 1));
      await pumpEventQueue();
      box.restartBehavior = (_) async => throw StateError('reload failed');
      await port.request(_on(2, rev: 2));
      await pumpEventQueue();
      expect(last().desired, Desired.off);
      expect(last().lastFailure?.code, KernelFailureCode.startService);
      expect(last().lastFailure?.seq, 2);
      expect(last().lastFailure?.attempt, 2);
      expect(last().status, KernelStatus.stopped);
    });
  });

  group('手选重放', () {
    test('acknowledgeReplay 幂等：attempt 不符忽略，重复确认不产生新快照', () async {
      await setUp0();
      await port.request(_on(1));
      await pumpEventQueue();
      expect(last().selectionsReplayNeeded, isTrue);

      await port.acknowledgeReplay(99);
      expect(last().selectionsReplayNeeded, isTrue);

      await port.acknowledgeReplay(1);
      await pumpEventQueue();
      expect(last().selectionsReplayNeeded, isFalse);
      final n = seen.length;
      await port.acknowledgeReplay(1);
      await pumpEventQueue();
      expect(seen, hasLength(n));
    });

    test('selectOutbound：expectedAttempt 不符 → stale 且不调用平台；相符 → ok', () async {
      await setUp0();
      await port.request(_on(1));
      await pumpEventQueue();

      final stale = await port.selectOutbound('g', 't', expectedAttempt: 7);
      expect(stale, isA<SelectStale>());
      expect(box.calls.where((c) => c.startsWith('select')), isEmpty);

      expect(
        await port.selectOutbound('g', 't', expectedAttempt: 1),
        isA<SelectOk>(),
      );
      expect(await port.selectOutbound('g', 't2'), isA<SelectOk>());
      expect(box.calls.where((c) => c.startsWith('select')), [
        'select:g/t',
        'select:g/t2',
      ]);

      box.selectBehavior = (_, _) async =>
          throw PlatformException(code: 'E_SEL', message: 'nope');
      final failed = await port.selectOutbound('g', 't3', expectedAttempt: 1);
      expect(failed, isA<SelectFailed>());
      expect((failed as SelectFailed).code, 'E_SEL');
    });
  });

  group('平台自身的变化（source=system）', () {
    test('运行中平台报告 Stopped（系统设置关闭/意外退出）：desired off、system、无 failure', () async {
      await setUp0();
      await port.request(_on(1));
      await pumpEventQueue();
      box.status.add(const BoxStopped());
      await pumpEventQueue();
      expect(last().status, KernelStatus.stopped);
      expect(last().desired, Desired.off);
      expect(last().source, DesiredSource.system);
      expect(last().lastFailure, isNull);
      expect(last().appliedSeq, 1);
      expect(box.calls, ['start:/rc/runtime-config-1.json'], reason: '不会自动拉起');
    });

    test('平台外部启动：attempt+1、desired on、system、要求重放', () async {
      await setUp0();
      box.status.add(const BoxStarting());
      await pumpEventQueue();
      expect(last().status, KernelStatus.starting);
      expect(last().attempt, 1);
      box.status.add(const BoxStarted());
      await pumpEventQueue();
      expect(last().status, KernelStatus.started);
      expect(last().attempt, 1);
      expect(last().desired, Desired.on);
      expect(last().source, DesiredSource.system);
      expect(last().selectionsReplayNeeded, isTrue);
      expect(box.calls, isEmpty);
    });

    test('外部启动后用户发 on（未知运行配置）：按 revision 差异重载一次', () async {
      await setUp0(initial: const BoxStarted());
      await port.request(_on(1, rev: 4));
      await pumpEventQueue();
      expect(box.calls, ['restart:/rc/runtime-config-1.json']);
      expect(last().activeConfigRevision, 4);
      expect(last().attempt, 1);
    });
  });

  test('链路恒为 connected', () async {
    await setUp0();
    expect(await port.watchLink().first, KernelLink.connected);
  });

  test('current() 在平台状态流无任何事件时 2 s 超时抛 KernelPortException', () {
    fakeAsync((async) {
      final silent = _SilentBox();
      final p = EmulatedKernelPort(silent, epochGenerator: () => 'ep');
      Object? error;
      p.current().then<void>((_) {}, onError: (Object e) => error = e);
      async.elapse(const Duration(milliseconds: 1999));
      expect(error, isNull);
      async.elapse(const Duration(milliseconds: 2));
      expect(error, isA<KernelPortException>());
      expect((error! as KernelPortException).code, 'timeout');
      p.dispose();
      async.flushMicrotasks();
    });
  });
}

/// 平台状态流永远不推任何事件（也不结束）。
class _SilentBox extends FakeBoxService {
  @override
  Stream<BoxStatus> watchStatus() =>
      Stream<BoxStatus>.fromFuture(Completer<BoxStatus>().future);
}
