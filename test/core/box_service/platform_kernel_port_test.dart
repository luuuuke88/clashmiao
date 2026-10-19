import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/pigeon/box_api.g.dart' as pigeon;
import 'package:clashmiao/core/box_service/platform_kernel_port.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _codec = pigeon.BoxHostApi.pigeonChannelCodec;

Map<String, Object?> _event({
  String epoch = 'e1',
  int version = 1,
  String status = 'started',
  int attempt = 1,
  String desired = 'on',
  int appliedSeq = 0,
}) => {
  'epoch': epoch,
  'version': version,
  'status': status,
  'attempt': attempt,
  'desired': desired,
  'source': 'app',
  'appliedSeq': appliedSeq,
  'activeConfigRevision': null,
  'selectionsReplayNeeded': false,
  'lastFailure': null,
};

pigeon.KernelSnapshotMsg _msg({
  String epoch = 'e1',
  int version = 1,
  String status = 'started',
  pigeon.KernelFailureMsg? failure,
}) => pigeon.KernelSnapshotMsg(
  epoch: epoch,
  version: version,
  status: status,
  attempt: 1,
  desired: 'on',
  source: 'app',
  appliedSeq: 0,
  selectionsReplayNeeded: false,
  lastFailure: failure,
);

void _mockHost(
  String method,
  Future<Object?> Function(List<Object?> args) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
        'dev.flutter.pigeon.clashmiao.BoxHostApi.$method',
        (ByteData? message) async {
          final args = message == null
              ? <Object?>[]
              : (_codec.decodeMessage(message) as List<Object?>? ?? []);
          try {
            return _codec.encodeMessage(<Object?>[await handler(args)]);
          } on PlatformException catch (e) {
            return _codec.encodeMessage(<Object?>[
              e.code,
              e.message,
              e.details,
            ]);
          }
        },
      );
}

/// 可手动喂事件/报错的事件流工厂，记录订阅次数。
class _Events {
  final controllers = <StreamController<Object?>>[];
  int get subscriptions => controllers.length;

  Stream<Object?> call() {
    final c = StreamController<Object?>();
    controllers.add(c);
    return c.stream;
  }

  StreamController<Object?> get last => controllers.last;

  Future<void> closeAll() async {
    for (final c in controllers) {
      if (!c.isClosed) await c.close();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final m in [
      'getSnapshot',
      'request',
      'acknowledgeReplay',
      'selectOutbound',
    ]) {
      messenger.setMockMessageHandler(
        'dev.flutter.pigeon.clashmiao.BoxHostApi.$m',
        null,
      );
    }
  });

  group('Pigeon 往返', () {
    test('getSnapshot 解码为 KernelSnapshot（含 lastFailure）', () async {
      _mockHost(
        'getSnapshot',
        (_) async => _msg(
          version: 9,
          failure: pigeon.KernelFailureMsg(
            code: 'kernelExited',
            message: 'boom',
            attempt: 2,
            seq: 4,
          ),
        ),
      );
      final port = PlatformKernelPort(eventStream: _Events().call);
      final s = await port.current();
      expect(s.version, 9);
      expect(s.status, KernelStatus.started);
      expect(s.lastFailure?.code, KernelFailureCode.kernelExited);
      expect(s.lastFailure?.seq, 4);
      await port.dispose();
    });

    test('request 编码请求字段，回执解码（受理 / stale / wrongEpoch）', () async {
      pigeon.DesiredRequestMsg? sent;
      var reply = pigeon.ReceiptMsg(accepted: true, epoch: 'e1', appliedSeq: 3);
      _mockHost('request', (args) async {
        sent = args[0]! as pigeon.DesiredRequestMsg;
        return reply;
      });
      final port = PlatformKernelPort(eventStream: _Events().call);
      final receipt = await port.request(
        DesiredRequest(
          epoch: 'e1',
          seq: 3,
          desired: Desired.on,
          reason: RequestReason.applyConfig,
          launch: const LaunchSpec(
            runtimeConfigPath: '/a/runtime-config-3.json',
            optionsJson: '{"x":1}',
            profileName: 'p',
            configRevision: 42,
          ),
        ),
      );
      expect(
        receipt,
        const RequestReceipt(accepted: true, epoch: 'e1', appliedSeq: 3),
      );
      expect(sent?.epoch, 'e1');
      expect(sent?.seq, 3);
      expect(sent?.desired, 'on');
      expect(sent?.reason, 'applyConfig');
      expect(sent?.launch?.runtimeConfigPath, '/a/runtime-config-3.json');
      expect(sent?.launch?.optionsJson, '{"x":1}');
      expect(sent?.launch?.profileName, 'p');
      expect(sent?.launch?.configRevision, 42);

      reply = pigeon.ReceiptMsg(
        accepted: false,
        reason: 'stale',
        epoch: 'e1',
        appliedSeq: 5,
      );
      final stale = await port.request(
        DesiredRequest(
          epoch: 'e1',
          seq: 3,
          desired: Desired.off,
          reason: RequestReason.userDisconnect,
        ),
      );
      expect(stale.accepted, isFalse);
      expect(stale.reason, RequestRejection.stale);
      expect(stale.appliedSeq, 5);

      reply = pigeon.ReceiptMsg(
        accepted: false,
        reason: 'wrongEpoch',
        epoch: 'e2',
        appliedSeq: 0,
      );
      final wrong = await port.request(
        DesiredRequest(
          epoch: 'e1',
          seq: 9,
          desired: Desired.off,
          reason: RequestReason.userDisconnect,
        ),
      );
      expect(wrong.reason, RequestRejection.wrongEpoch);
      expect(wrong.epoch, 'e2');
      await port.dispose();
    });

    test('原生 FlutterError（unimplemented）包装为 KernelPortException', () async {
      _mockHost(
        'request',
        (_) async =>
            throw PlatformException(code: 'unimplemented', message: 'x'),
      );
      final port = PlatformKernelPort(eventStream: _Events().call);
      await expectLater(
        port.request(
          DesiredRequest(
            epoch: 'e1',
            seq: 1,
            desired: Desired.off,
            reason: RequestReason.userDisconnect,
          ),
        ),
        throwsA(
          isA<KernelPortException>().having(
            (e) => e.code,
            'code',
            'unimplemented',
          ),
        ),
      );
      await port.dispose();
    });

    test('acknowledgeReplay 传 attempt', () async {
      int? got;
      _mockHost('acknowledgeReplay', (args) async {
        got = args[0] as int?;
        return null;
      });
      final port = PlatformKernelPort(eventStream: _Events().call);
      await port.acknowledgeReplay(4);
      expect(got, 4);
      await port.dispose();
    });

    test(
      'selectOutbound：ok / stale / failed 三种结果，expectedAttempt 透传',
      () async {
        pigeon.SelectOutboundRequest? sent;
        Object? error;
        _mockHost('selectOutbound', (args) async {
          sent = args[0]! as pigeon.SelectOutboundRequest;
          final e = error;
          if (e != null) throw e;
          return null;
        });
        final port = PlatformKernelPort(eventStream: _Events().call);

        expect(
          await port.selectOutbound('g', 't', expectedAttempt: 3),
          isA<SelectOk>(),
        );
        expect(sent?.groupTag, 'g');
        expect(sent?.outboundTag, 't');
        expect(sent?.expectedAttempt, 3);

        error = PlatformException(code: 'stale', message: 'attempt mismatch');
        expect(
          await port.selectOutbound('g', 't', expectedAttempt: 2),
          isA<SelectStale>(),
        );

        error = PlatformException(code: 'E_KERNEL', message: 'no such group');
        final failed = await port.selectOutbound('g', 't');
        expect(failed, isA<SelectFailed>());
        expect((failed as SelectFailed).code, 'E_KERNEL');
        expect(failed.message, 'no such group');
        expect(sent?.expectedAttempt, isNull);
        await port.dispose();
      },
    );
  });

  group('超时', () {
    test('request / current 超过 2 s 抛 KernelPortException(timeout)', () {
      fakeAsync((async) {
        _mockHost('request', (_) => Completer<Object?>().future);
        _mockHost('getSnapshot', (_) => Completer<Object?>().future);
        final port = PlatformKernelPort(eventStream: _Events().call);
        final errors = <Object>[];
        port
            .request(
              DesiredRequest(
                epoch: 'e1',
                seq: 1,
                desired: Desired.off,
                reason: RequestReason.userDisconnect,
              ),
            )
            .then<void>((_) {}, onError: errors.add);
        port.current().then<void>((_) {}, onError: errors.add);
        async.elapse(const Duration(milliseconds: 1999));
        expect(errors, isEmpty);
        async.elapse(const Duration(milliseconds: 2));
        expect(errors, hasLength(2));
        expect(errors, everyElement(isA<KernelPortException>()));
        expect(
          errors.cast<KernelPortException>().map((e) => e.code),
          everyElement('timeout'),
        );
      });
    });
  });

  group('快照版本过滤（spec §10.5）', () {
    test('旧 version / 重复 version 丢弃，更大 version 接受，新 epoch 接受', () async {
      _mockHost('getSnapshot', (_) async => _msg(version: 5));
      final events = _Events();
      final port = PlatformKernelPort(eventStream: events.call);
      final seen = <KernelSnapshot>[];
      final sub = port.watch().listen(seen.add);
      await pumpEventQueue();

      events.last
        ..add(_event(version: 5))
        ..add(_event(version: 4)) // 旧
        ..add(_event(version: 5)) // 重复
        ..add(_event(version: 6, status: 'stopping'))
        ..add(_event(epoch: 'e2', version: 1, status: 'stopped')) // 新纪元
        ..add(_event(epoch: 'e1', version: 99)) // 回到旧纪元：纪元不同，但来自当前订阅 → 按规则接受
        ..add('not a map')
        ..add({'epoch': 'e2'}); // 非法载荷丢弃
      await pumpEventQueue();

      expect(seen.map((s) => '${s.epoch}/${s.version}'), [
        'e1/5',
        'e1/6',
        'e2/1',
        'e1/99',
      ]);
      await sub.cancel();
      await events.closeAll();
      await port.dispose();
    });

    test('过期查询 token 的结果丢弃，返回较新查询已接受的快照', () async {
      final gates = <Completer<pigeon.KernelSnapshotMsg>>[];
      _mockHost('getSnapshot', (_) {
        final c = Completer<pigeon.KernelSnapshotMsg>();
        gates.add(c);
        return c.future;
      });
      final port = PlatformKernelPort(eventStream: _Events().call);
      final seen = <KernelSnapshot>[];
      final sub = port.watch().listen(seen.add);
      await pumpEventQueue();
      // watch 订阅触发的重新同步占用第 0 个查询；它先被两个显式查询超越。
      final first = port.current();
      final second = port.current();
      await pumpEventQueue();
      expect(gates, hasLength(3));

      // 较新的查询先返回 e1/12，被接受。
      gates[2].complete(_msg(version: 12));
      expect(
        await second,
        isA<KernelSnapshot>().having((s) => s.version, 'version', 12),
      );
      // 过期查询随后带着新纪元的快照返回——token 过期，丢弃。
      gates[1].complete(_msg(epoch: 'ghost', version: 1));
      final stale = await first;
      expect(stale.epoch, 'e1');
      expect(stale.version, 12);
      gates[0].complete(_msg(version: 3));
      await pumpEventQueue();

      expect(seen.map((s) => '${s.epoch}/${s.version}'), ['e1/12']);
      await sub.cancel();
      await port.dispose();
    });

    test('流里已接受更新的快照后，在途查询的旧结果被丢弃', () async {
      final gate = Completer<pigeon.KernelSnapshotMsg>();
      _mockHost('getSnapshot', (_) => gate.future);
      final events = _Events();
      final port = PlatformKernelPort(eventStream: events.call);
      final seen = <KernelSnapshot>[];
      final sub = port.watch().listen(seen.add);
      await pumpEventQueue();

      events.last.add(_event(epoch: 'e2', version: 3));
      await pumpEventQueue();
      gate.complete(_msg(epoch: 'e1', version: 50)); // 查询发起早于新纪元事件
      await pumpEventQueue();

      expect(seen.map((s) => '${s.epoch}/${s.version}'), ['e2/3']);
      await sub.cancel();
      await events.closeAll();
      await port.dispose();
    });

    test('订阅者订阅时先收到当前已知快照', () async {
      _mockHost('getSnapshot', (_) async => _msg(version: 2));
      final events = _Events();
      final port = PlatformKernelPort(eventStream: events.call);
      final a = <int>[];
      final subA = port.watch().listen((s) => a.add(s.version));
      await pumpEventQueue();
      expect(a, [2]);
      final b = <int>[];
      final subB = port.watch().listen((s) => b.add(s.version));
      await pumpEventQueue();
      expect(b, [2]);
      expect(events.subscriptions, 1, reason: '多个订阅者共用一条原生订阅');
      await subA.cancel();
      await subB.cancel();
      await events.closeAll();
      await port.dispose();
    });
  });

  group('订阅轮次与查询代际隔离（spec §10.5 / §10.8）', () {
    /// 每次 getSnapshot 调用登记一个 gate，由测试决定何时、如何返回。
    List<Completer<pigeon.KernelSnapshotMsg>> mockGates() {
      final gates = <Completer<pigeon.KernelSnapshotMsg>>[];
      _mockHost('getSnapshot', (_) {
        final c = Completer<pigeon.KernelSnapshotMsg>();
        gates.add(c);
        return c.future;
      });
      return gates;
    }

    test('旧一轮的同步迟到成功：不缓存、不推快照、不把断开的链路改回 connected', () {
      fakeAsync((async) {
        final gates = mockGates();
        final events = _Events();
        final port = PlatformKernelPort(eventStream: events.call);
        final links = <KernelLink>[];
        final seen = <int>[];
        final subL = port.watchLink().listen(links.add);
        final subS = port.watch().listen((s) => seen.add(s.version));
        async.flushMicrotasks();
        expect(gates, hasLength(1));

        events.last.addError(StateError('x')); // 第 1 轮在同步返回前结束
        async.flushMicrotasks();
        expect(links.last, KernelLink.lost);

        gates[0].complete(_msg(version: 3)); // 退避窗口内，旧同步迟到成功
        async.flushMicrotasks();
        expect(seen, isEmpty);
        expect(links.last, KernelLink.lost);

        async.elapse(const Duration(milliseconds: 501)); // 第 2 轮
        expect(events.subscriptions, 2);
        expect(gates, hasLength(2));
        gates[1].complete(_msg(version: 5));
        async.flushMicrotasks();
        expect(seen, [5]);
        expect(links.last, KernelLink.connected);

        subL.cancel();
        subS.cancel();
        async.flushMicrotasks();
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('旧一轮的同步迟到失败：不会把已恢复的新一轮标成失联，也不触发多余重订阅', () {
      fakeAsync((async) {
        final gates = mockGates();
        final events = _Events();
        final port = PlatformKernelPort(eventStream: events.call);
        final links = <KernelLink>[];
        final subL = port.watchLink().listen(links.add);
        final subS = port.watch().listen((_) {});
        async.flushMicrotasks();

        events.last.addError(StateError('x'));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 501));
        expect(events.subscriptions, 2);
        gates[1].complete(_msg(version: 5)); // 新一轮恢复
        async.flushMicrotasks();
        expect(links.last, KernelLink.connected);

        gates[0].completeError(
          PlatformException(code: 'channel-error', message: 'late'),
        );
        async.flushMicrotasks();
        expect(links.last, KernelLink.connected);
        async.elapse(const Duration(seconds: 30));
        expect(events.subscriptions, 2);
        expect(links.last, KernelLink.connected);

        subL.cancel();
        subS.cancel();
        async.flushMicrotasks();
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('取消全部订阅后返回的在途查询：不回填已清空的缓存，下一批订阅者不会先收到它', () async {
      final gates = mockGates();
      final events = _Events();
      final port = PlatformKernelPort(eventStream: events.call);
      final sub = port.watch().listen((_) {});
      await pumpEventQueue();
      expect(gates, hasLength(1));

      await sub.cancel();
      await pumpEventQueue();
      gates[0].complete(_msg(version: 3)); // 取消之后才返回
      await pumpEventQueue();

      final seen2 = <int>[];
      final sub2 = port.watch().listen((s) => seen2.add(s.version));
      await pumpEventQueue();
      expect(seen2, isEmpty, reason: '旧查询的 v3 不得被缓存并回放');
      expect(gates, hasLength(2));
      gates[1].complete(_msg(version: 9));
      await pumpEventQueue();
      expect(seen2, [9]);

      await sub2.cancel();
      await events.closeAll();
      await port.dispose();
    });

    test('取消后无订阅时的查询不缓存，但调用方仍拿到自己的结果', () async {
      _mockHost('getSnapshot', (_) async => _msg(version: 4));
      final port = PlatformKernelPort(eventStream: _Events().call);
      expect((await port.current()).version, 4);
      final seen = <int>[];
      final sub = port.watch().listen((s) => seen.add(s.version));
      await pumpEventQueue();
      // 订阅触发的重新同步给出 v4，是订阅者看到的第一份，而不是先回放旧缓存。
      expect(seen, [4]);
      await sub.cancel();
      await port.dispose();
    });
  });

  group('current() 整体 2 s 截止（spec §2）', () {
    test('重叠查询：旧查询等待较新结果时只花剩余预算，不被连续查询拖长', () {
      fakeAsync((async) {
        final gates = <Completer<pigeon.KernelSnapshotMsg>>[];
        _mockHost('getSnapshot', (_) {
          final c = Completer<pigeon.KernelSnapshotMsg>();
          gates.add(c);
          return c.future;
        });
        final port = PlatformKernelPort(eventStream: _Events().call);
        final results = <String, Object>{};
        void track(String name, Future<KernelSnapshot> f) {
          f.then<void>(
            (s) => results[name] = s,
            onError: (Object e) => results[name] = e,
          );
        }

        track('A', port.current()); // t = 0
        async.elapse(const Duration(milliseconds: 1500));
        track('B', port.current()); // t = 1.5 s
        async.elapse(const Duration(milliseconds: 400)); // t = 1.9 s
        gates[0].complete(_msg(version: 1)); // A 的 RPC 返回，但已被 B 取代
        async.flushMicrotasks();
        expect(results, isEmpty, reason: 'A 在等 B 的结果');

        async.elapse(const Duration(milliseconds: 99)); // t = 1.999 s
        expect(results, isEmpty);
        async.elapse(const Duration(milliseconds: 2)); // t = 2.001 s
        expect(results['A'], isA<KernelPortException>());
        expect((results['A']! as KernelPortException).code, 'timeout');
        expect(results.containsKey('B'), isFalse);

        async.elapse(const Duration(milliseconds: 1500)); // t = 3.501 s
        expect((results['B']! as KernelPortException).code, 'timeout');
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('被取代的旧查询在较新查询先返回时，立刻拿到较新的结果', () {
      fakeAsync((async) {
        final gates = <Completer<pigeon.KernelSnapshotMsg>>[];
        _mockHost('getSnapshot', (_) {
          final c = Completer<pigeon.KernelSnapshotMsg>();
          gates.add(c);
          return c.future;
        });
        final port = PlatformKernelPort(eventStream: _Events().call);
        KernelSnapshot? a;
        port.current().then<void>((s) => a = s);
        async.elapse(const Duration(milliseconds: 500));
        port.current();
        gates[0].complete(_msg(version: 1));
        async.flushMicrotasks();
        expect(a, isNull);
        gates[1].complete(_msg(version: 7));
        async.flushMicrotasks();
        expect(a?.version, 7);
        port.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('重订阅与重新同步（spec §10.8）', () {
    test('流报错后按 0.5/1/2/4/4 s 退避重订阅，每次重订阅后重新同步', () {
      fakeAsync((async) {
        var queries = 0;
        _mockHost('getSnapshot', (_) async {
          queries++;
          return _msg(version: queries);
        });
        final events = _Events();
        final port = PlatformKernelPort(eventStream: events.call);
        final sub = port.watch().listen((_) {});
        async.flushMicrotasks();
        expect(events.subscriptions, 1);
        expect(queries, 1);

        void failLatest() {
          events.last.addError(StateError('boom'));
          async.flushMicrotasks();
        }

        // t=0 报错 → 0.5 s 后第 2 次订阅
        failLatest();
        async.elapse(const Duration(milliseconds: 499));
        expect(events.subscriptions, 1);
        async.elapse(const Duration(milliseconds: 2));
        expect(events.subscriptions, 2);
        expect(queries, 2);

        failLatest(); // 1 s
        async.elapse(const Duration(milliseconds: 999));
        expect(events.subscriptions, 2);
        async.elapse(const Duration(milliseconds: 2));
        expect(events.subscriptions, 3);

        failLatest(); // 2 s
        async.elapse(const Duration(milliseconds: 1999));
        expect(events.subscriptions, 3);
        async.elapse(const Duration(milliseconds: 2));
        expect(events.subscriptions, 4);

        failLatest(); // 4 s
        async.elapse(const Duration(milliseconds: 3999));
        expect(events.subscriptions, 4);
        async.elapse(const Duration(milliseconds: 2));
        expect(events.subscriptions, 5);

        failLatest(); // 封顶 4 s
        async.elapse(const Duration(milliseconds: 3999));
        expect(events.subscriptions, 5);
        async.elapse(const Duration(milliseconds: 2));
        expect(events.subscriptions, 6);
        expect(queries, 6);

        sub.cancel();
        async.flushMicrotasks();
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('流正常结束同样触发重订阅；链路 lost → connected，退避随成功重置', () {
      fakeAsync((async) {
        _mockHost('getSnapshot', (_) async => _msg(version: 1));
        final events = _Events();
        final port = PlatformKernelPort(eventStream: events.call);
        final links = <KernelLink>[];
        final subL = port.watchLink().listen(links.add);
        final subS = port.watch().listen((_) {});
        async.flushMicrotasks();
        expect(links.first, KernelLink.lost, reason: '上游刚启动，保守地不谎报在线');
        expect(links.last, KernelLink.connected);

        // 第一次断线：0.5 s 后恢复
        events.last.addError(StateError('x'));
        async.flushMicrotasks();
        expect(links.last, KernelLink.lost);
        async.elapse(const Duration(milliseconds: 501));
        expect(events.subscriptions, 2);
        events.last.add(_event(version: 7));
        async.flushMicrotasks();
        expect(links.last, KernelLink.connected);

        // 成功之后再断：退避从 0.5 s 重新开始，而不是 1 s
        events.last.close();
        async.flushMicrotasks();
        expect(links.last, KernelLink.lost);
        async.elapse(const Duration(milliseconds: 501));
        expect(events.subscriptions, 3);

        subL.cancel();
        subS.cancel();
        async.flushMicrotasks();
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('首次 current() 失败：按同一退避重试，成功后推出快照', () {
      fakeAsync((async) {
        var queries = 0;
        _mockHost('getSnapshot', (_) async {
          queries++;
          if (queries < 3) {
            throw PlatformException(code: 'channel-error', message: 'down');
          }
          return _msg(version: 8);
        });
        final events = _Events(); // 流本身一直开着但不推数据
        final port = PlatformKernelPort(eventStream: events.call);
        final seen = <int>[];
        final links = <KernelLink>[];
        final subL = port.watchLink().listen(links.add);
        final subS = port.watch().listen((s) => seen.add(s.version));
        async.flushMicrotasks();
        expect(queries, 1);
        expect(events.subscriptions, 1);
        expect(links.last, KernelLink.lost);

        async.elapse(const Duration(milliseconds: 501)); // 0.5 s
        expect(queries, 2);
        expect(events.subscriptions, 2);
        async.elapse(const Duration(milliseconds: 1001)); // 1 s
        expect(queries, 3);
        expect(seen, [8]);
        expect(links.last, KernelLink.connected);

        subL.cancel();
        subS.cancel();
        async.flushMicrotasks();
        port.dispose();
        async.flushMicrotasks();
      });
    });

    test('最后一个订阅者离开后停止订阅，不再重试', () {
      fakeAsync((async) {
        _mockHost('getSnapshot', (_) async => _msg());
        final events = _Events();
        final port = PlatformKernelPort(eventStream: events.call);
        final sub = port.watch().listen((_) {});
        async.flushMicrotasks();
        events.last.addError(StateError('x'));
        async.flushMicrotasks();
        sub.cancel();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(events.subscriptions, 1);
        port.dispose();
        async.flushMicrotasks();
      });
    });
  });
}
