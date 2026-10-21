import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/domain/connection/application/connection_providers.dart';
import 'package:clashmiao/core/box_service/model/box_status.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/latency_test_coordinator.dart';
import 'package:clashmiao/domain/connection/application/latency_test_wiring.dart';
import 'package:clashmiao/domain/routing/model/cached_delay.dart';
import 'package:collection/collection.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_box_service.dart';

final _t0 = DateTime(2026, 10, 20, 12);

OutboundGroup _group(
  Map<String, int> delays, {
  String tag = 'proxy',
  String type = 'selector',
}) => OutboundGroup(
  tag: tag,
  type: type,
  selected: delays.keys.firstOrNull ?? '',
  items: [
    for (final e in delays.entries)
      OutboundProxy(tag: e.key, type: 'vmess', delay: e.value),
  ],
);

/// 不依赖 Riverpod 的协调器测试台：时间全部来自 fake_async。
class _Rig {
  _Rig(this.async, {Map<String, CachedDelay>? cache}) {
    this.cache = cache ?? {};
    coordinator = LatencyTestCoordinator(
      urlTest: (group) {
        urlTests.add(group);
        return urlTestResult?.call() ?? Future<void>.value();
      },
      liveGroups: () => groups,
      cache: () => this.cache,
      recordMeasured: (ms, at) {
        recorded.add((Map.of(ms), at));
        for (final e in ms.entries) {
          this.cache[e.key] = CachedDelay(e.value, at);
        }
      },
      recordFailed: (tags, at) {
        failed.add((Set.of(tags), at));
        for (final tag in tags) {
          this.cache[tag] = CachedDelay.failed(at);
        }
      },
      now: () => _t0.add(async.elapsed),
    );
  }

  final FakeAsync async;
  late final Map<String, CachedDelay> cache;
  late final LatencyTestCoordinator coordinator;
  final List<String> urlTests = [];
  final List<(Map<String, int>, DateTime)> recorded = [];
  final List<(Set<String>, DateTime)> failed = [];
  Future<void> Function()? urlTestResult;
  List<OutboundGroup> groups = [];

  void elapse(Duration d) => async.elapse(d);

  /// 模拟分组流推来一份新数据。
  void push(List<OutboundGroup> next) {
    groups = next;
    coordinator.onGroups(next);
  }
}

void _fake(
  String name,
  void Function(_Rig rig, FakeAsync async) body, {
  Map<String, CachedDelay>? cache,
}) {
  test(name, () {
    fakeAsync((async) {
      final rig = _Rig(async, cache: cache);
      body(rig, async);
      rig.coordinator.dispose();
    });
  });
}

void main() {
  group('进入 connected 后 2 s 预热测速', () {
    _fake('2 s 前不测，2 s 到点测一次当前组', (rig, async) {
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);

      rig.elapse(const Duration(milliseconds: 1999));
      expect(rig.urlTests, isEmpty);
      rig.elapse(const Duration(milliseconds: 1));
      expect(rig.urlTests, ['proxy']);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
    });

    _fake('2 s 到了但目标组还没数据：等分组到达后再测', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 3));
      expect(rig.urlTests, isEmpty);

      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.urlTests, ['proxy']);
    });

    _fake('目标组不可测速（空组）时不测', (rig, async) {
      rig.groups = [_group({}, tag: 'proxy')];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 3));
      expect(rig.urlTests, isEmpty);
    });

    _fake('预热只测主分组：跳过 GLOBAL 与等价的重复分组', (rig, async) {
      rig.groups = [
        _group({'a': 0}, tag: 'GLOBAL'),
        _group({'a': 0}, tag: 'proxy'),
        _group({'a': 0}, tag: 'Auto', type: 'urltest'),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      expect(rig.urlTests, ['proxy']);
    });
  });

  group('30 s 去重', () {
    _fake('同组 30 s 内的自动请求被去重，满 30 s 后放行', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      expect(rig.urlTests, hasLength(1));

      // 第一轮超时结束（17 s）。
      rig.elapse(kLatencyRoundTimeout);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);

      rig.coordinator.requestAuto('proxy'); // 距首次开测 17 s
      expect(rig.urlTests, hasLength(1));

      // 首次开测发生在 t=2 s，冷却到 t=32 s 才结束。
      rig.elapse(const Duration(milliseconds: 12999)); // t = 31.999 s
      rig.coordinator.requestAuto('proxy');
      expect(rig.urlTests, hasLength(1));

      rig.elapse(const Duration(milliseconds: 1)); // t = 32 s
      rig.coordinator.requestAuto('proxy');
      expect(rig.urlTests, hasLength(2));
    });

    _fake('在途时自动请求直接忽略，不重复开测', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.coordinator.requestAuto('proxy');
      expect(rig.urlTests, hasLength(1));
    });

    _fake('不同分组各自计时', (rig, async) {
      rig.groups = [
        _group({'a': 0}, tag: 'g1'),
        _group({'b': 0}, tag: 'g2'),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.coordinator.requestAuto('g1');
      rig.coordinator.requestAuto('g2');
      expect(rig.urlTests, ['g1', 'g2']);
    });
  });

  group('手动测速', () {
    _fake('绕过冷却：刚自动测完也能立刻手动再测', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(kLatencyRoundTimeout); // 第一轮超时收尾
      expect(rig.urlTests, hasLength(1));

      unawaited(rig.coordinator.manualTest('proxy'));
      expect(rig.urlTests, hasLength(2));
    });

    _fake('复用在途任务：只调一次 urlTest，两个调用方一起等到结束', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      var first = false;
      var second = false;
      unawaited(rig.coordinator.manualTest('proxy').then((_) => first = true));
      unawaited(rig.coordinator.manualTest('proxy').then((_) => second = true));
      async.flushMicrotasks();
      expect(rig.urlTests, ['proxy']);
      expect(first || second, isFalse);

      rig.elapse(kLatencyRoundTimeout);
      expect(first && second, isTrue);
    });

    _fake('内核报错：手动调用方拿到异常，状态收尾，不标超时', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.urlTestResult = () async => throw StateError('boom');
      Object? error;
      unawaited(
        rig.coordinator
            .manualTest('proxy')
            .then<void>(
              (_) {},
              onError: (Object e) {
                error = e;
              },
            ),
      );
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);

      // 失败那一轮的超时定时器已被取消：之后什么都不会被标成超时。
      rig.elapse(const Duration(seconds: 20));
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('自动开测后手动加入、随后内核报错：手动调用方同样拿到异常', (rig, async) {
      final failure = Completer<void>();
      rig.urlTestResult = () => failure.future;
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2)); // 自动轮次开测
      expect(rig.urlTests, ['proxy']);

      final errors = <Object>[];
      for (var i = 0; i < 2; i++) {
        unawaited(
          rig.coordinator
              .manualTest('proxy')
              .then<void>((_) {}, onError: errors.add),
        );
      }
      async.flushMicrotasks();
      expect(rig.urlTests, ['proxy'], reason: '手动复用在途的自动轮次');
      expect(errors, isEmpty);

      failure.completeError(StateError('boom'));
      async.flushMicrotasks();
      expect(errors, hasLength(2), reason: '每个手动等待者都收到这一轮的异常');
      expect(errors, everyElement(isA<StateError>()));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('纯自动轮次内核报错：没有手动等待者，异常不外溢', (rig, async) {
      rig.urlTestResult = () async => throw StateError('boom');
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(rig.urlTests, ['proxy']);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
    });

    _fake('未连接时手动测速什么都不做', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      var done = false;
      unawaited(rig.coordinator.manualTest('proxy').then((_) => done = true));
      async.flushMicrotasks();
      expect(done, isTrue);
      expect(rig.urlTests, isEmpty);
    });
  });

  group('取消', () {
    _fake('断开：在途任务被取消、预热定时器被取消', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      var done = false;
      unawaited(rig.coordinator.manualTest('proxy').then((_) => done = true));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);

      rig.coordinator.onConnectionChanged(false);
      async.flushMicrotasks();
      expect(done, isTrue, reason: '等待中的调用方被放行而不是永远挂起');
      expect(rig.coordinator.state.testingGroups, isEmpty);
      expect(async.nonPeriodicTimerCount, 0, reason: '超时定时器也被清掉');

      // 断开后再过多久都不会冒出新的测速。
      rig.elapse(const Duration(minutes: 1));
      expect(rig.urlTests, hasLength(1));
    });

    _fake('断开发生在 2 s 预热之前：预热不再触发', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 1));
      rig.coordinator.onConnectionChanged(false);
      rig.elapse(const Duration(seconds: 5));
      expect(rig.urlTests, isEmpty);
    });

    _fake('重连：旧任务取消，重新走 2 s 预热，且冷却清零', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      expect(rig.urlTests, hasLength(1));

      rig.coordinator.onConnectionChanged(false);
      rig.coordinator.onConnectionChanged(true);
      expect(rig.coordinator.state.testingGroups, isEmpty);
      rig.elapse(const Duration(seconds: 2));
      expect(rig.urlTests, hasLength(2), reason: '新连接不受上一次连接的 30 s 冷却约束');
    });

    _fake('切订阅：取消在途任务并清掉上一份订阅的超时标记', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(kLatencyRoundTimeout); // 超时，a 被标超时
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      unawaited(rig.coordinator.manualTest('proxy'));

      rig.coordinator.onProfileChanged();
      expect(rig.coordinator.state.testingGroups, isEmpty);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  group('完成条件：所有节点都有本轮结果，或到预算超时', () {
    _fake('全部节点都出了结果就立即收尾，不等超时', (rig, async) {
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));

      rig.push([
        _group({'a': 120, 'b': 0}),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);

      rig.push([
        _group({'a': 120, 'b': 300}),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(async.nonPeriodicTimerCount, 0, reason: '超时定时器随完成一起取消');
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.recorded.single.$1, {'a': 120, 'b': 300});
    });

    _fake('17 s 到点：还没结果的节点标为超时，有结果的写进缓存', (rig, async) {
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 150, 'b': 0}),
      ]);

      rig.elapse(kLatencyRoundTimeout - const Duration(milliseconds: 1));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
      rig.elapse(const Duration(milliseconds: 1));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, {'b'});
      expect(rig.recorded.single.$1, {'a': 150});
      expect(rig.failed.single.$1, {'b'}, reason: '超时的节点记成失败，写进缓存');
    });

    _fake('开测前就有旧值的节点：数值变化算出结果；失败变 0 也算出结果并标超时', (rig, async) {
      rig.groups = [
        _group({'a': 100, 'b': 200}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));

      rig.push([
        _group({'a': 130, 'b': 0}),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, {'b'});
    });

    _fake('内核立即回复 urlTest（测试只是开始）、同值且没变化：不刷新测量时间，显示历史值而非超时', (rig, async) {
      final measuredAt = _t0.subtract(const Duration(minutes: 1));
      rig.cache['a'] = CachedDelay(100, measuredAt);
      rig.groups = [
        _group({'a': 100}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      async.flushMicrotasks(); // urlTest 已正常返回

      // 分组流推来的值与开测基线相同。
      rig.push([
        _group({'a': 100}),
      ]);
      rig.elapse(kLatencyRoundTimeout);
      expect(rig.recorded, isEmpty, reason: '没确认的旧值不能记成本轮结果');
      expect(rig.cache['a'], CachedDelay(100, measuredAt));
      expect(rig.coordinator.state.unconfirmedNodes, {'a'});
      expect(
        rig.coordinator.state.timedOutNodes,
        isEmpty,
        reason: '稳定的快节点不能被标成超时',
      );
    });

    _fake('内核悬挂且没有任何分组事件：实时值有效的保留旧时间、显示历史值；实时值缺席的（只剩缓存旧数）标超时', (rig, async) {
      final hung = Completer<void>();
      rig.urlTestResult = () => hung.future;
      final aAt = _t0.subtract(const Duration(minutes: 2));
      rig.cache['a'] = CachedDelay(100, aAt);
      rig.cache['b'] = const CachedDelay(250, null); // 旧格式历史值
      rig.cache['c'] = CachedDelay(180, aAt); // 实时值缺席，只有缓存
      rig.groups = [
        _group({'a': 100, 'b': 250, 'c': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      var done = false;
      unawaited(rig.coordinator.manualTest('proxy').then((_) => done = true));
      expect(rig.urlTests, ['proxy']);

      rig.elapse(kLatencyRoundTimeout - const Duration(milliseconds: 1));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
      expect(rig.coordinator.state.pendingNodes['proxy'], {'a', 'b', 'c'});
      rig.elapse(const Duration(milliseconds: 1));

      expect(done, isTrue, reason: '超时收尾放行等待者，不跟着内核一起挂住');
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.pendingNodes, isEmpty);
      expect(rig.recorded, isEmpty);
      expect(rig.cache['a'], CachedDelay(100, aAt), reason: '保留原测量时间');
      expect(
        rig.cache['b'],
        const CachedDelay(250, null),
        reason: '旧格式历史值仍是历史值',
      );
      expect(rig.cache['c']!.isFailed, isTrue, reason: '缓存里的旧数不能顶替失败');
      expect(rig.coordinator.state.unconfirmedNodes, {'a', 'b'});
      expect(rig.coordinator.state.timedOutNodes, {'c'});
      expect(async.nonPeriodicTimerCount, 0);
      hung.complete();
    });

    _fake('开测前遗留超时哨兵 + 有效缓存 + 本轮无事件：失败压过缓存旧值，标超时；实时值有效的才算未确认', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      final oldAt = _t0.subtract(const Duration(minutes: 1));
      rig.cache['old-sentinel'] = CachedDelay(150, oldAt);
      rig.cache['fails-now'] = CachedDelay(120, oldAt);
      rig.cache['kept'] = CachedDelay(80, oldAt);
      rig.groups = [
        _group({'old-sentinel': 65535, 'fails-now': 120, 'kept': 80}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      // 只有 fails-now 在本轮出了结果：测失败，变成哨兵。
      rig.push([
        _group({'old-sentinel': 65535, 'fails-now': 65535, 'kept': 80}),
      ]);
      rig.elapse(kLatencyRoundTimeout);

      expect(rig.recorded, isEmpty);
      expect(rig.cache['old-sentinel']!.isFailed, isTrue);
      expect(rig.cache['fails-now']!.isFailed, isTrue);
      expect(rig.cache['kept'], CachedDelay(80, oldAt));
      expect(rig.coordinator.state.unconfirmedNodes, {'kept'});
      expect(rig.coordinator.state.timedOutNodes, {
        'old-sentinel',
        'fails-now',
      });
    });

    _fake('内核悬挂、一点旧值都没有的节点：到点标超时（本轮测了没结果）', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      unawaited(rig.coordinator.manualTest('proxy'));
      rig.elapse(kLatencyRoundTimeout);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
    });

    _fake('内核悬挂但部分分组事件到了：确认的刷新、没确认的显示历史值、确认失败与无值的标超时', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      final oldAt = _t0.subtract(const Duration(minutes: 3));
      rig.cache['ok'] = CachedDelay(100, oldAt);
      rig.cache['same'] = CachedDelay(200, oldAt);
      rig.cache['dead'] = CachedDelay(300, oldAt);
      rig.groups = [
        _group({'ok': 100, 'same': 200, 'dead': 300, 'none': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2)); // 自动开测
      rig.push([
        _group({'ok': 140, 'same': 200, 'dead': 0, 'none': 0}),
      ]);
      expect(rig.coordinator.state.pendingNodes['proxy'], {'same', 'none'});

      rig.elapse(kLatencyRoundTimeout);
      final (ms, at) = rig.recorded.single;
      expect(ms, {'ok': 140});
      expect(at, _t0.add(const Duration(seconds: 19)));
      expect(rig.cache['same'], CachedDelay(200, oldAt));
      expect(rig.coordinator.state.unconfirmedNodes, {'same'});
      expect(rig.coordinator.state.timedOutNodes, {'dead', 'none'});
      expect(rig.failed.single.$1, {'dead', 'none'});
    });

    _fake('内核测失败会删掉测速历史（分组流里是 0）：缓存里有 98 ms 的死节点到点标超时并记成失败，活节点刷新', (
      rig,
      async,
    ) {
      final oldAt = _t0.subtract(const Duration(days: 1));
      rig.cache['泰国'] = CachedDelay(98, oldAt);
      rig.cache['香港01'] = CachedDelay(123, oldAt);
      rig.cache['香港直连'] = CachedDelay(300, oldAt);
      // 死节点的历史早就被内核删了，开测前后都是 0。
      rig.groups = [
        _group({'泰国': 0, '香港01': 0, '香港直连': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'泰国': 0, '香港01': 0, '香港直连': 190}),
      ]);
      rig.elapse(kLatencyRoundTimeout);

      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, {'泰国', '香港01'});
      expect(
        rig.coordinator.state.unconfirmedNodes,
        isEmpty,
        reason: '缓存里的 98 ms 不能让死节点变成「历史值」',
      );
      expect(rig.failed.single.$1, {'泰国', '香港01'});
      expect(rig.cache['泰国']!.isFailed, isTrue);
      expect(rig.cache['香港01']!.isFailed, isTrue);
      expect(rig.recorded.single.$1, {'香港直连': 190});
      expect(
        rig.cache['香港直连'],
        CachedDelay(190, _t0.add(const Duration(seconds: 19))),
      );
    });

    _fake('成功的节点更新数值：旧失败记录被成功覆盖', (rig, async) {
      rig.cache['a'] = CachedDelay.failed(
        _t0.subtract(const Duration(hours: 1)),
      );
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 77}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(
        rig.cache['a'],
        CachedDelay(77, _t0.add(const Duration(seconds: 2))),
      );
      expect(rig.failed, isEmpty);
    });

    _fake('内核调用本身失败：不是节点的问题，不记任何失败', (rig, async) {
      rig.urlTestResult = () async => throw StateError('kernel down');
      rig.cache['a'] = CachedDelay(98, _t0);
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      unawaited(
        rig.coordinator.manualTest('proxy').then((_) {}, onError: (_) {}),
      );
      async.flushMicrotasks();
      expect(rig.failed, isEmpty);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.cache['a'], CachedDelay(98, _t0));
    });

    // ---- 预算：内核 10 路并发，每路最长 15 s（TCP 超时） ----

    _fake('预算公式：每批 15 s + 2 s 余量，按 10 个一批向上取整，封顶 60 s', (rig, async) {
      expect(latencyRoundTimeoutFor(1), const Duration(seconds: 17));
      expect(latencyRoundTimeoutFor(10), const Duration(seconds: 17));
      expect(latencyRoundTimeoutFor(11), const Duration(seconds: 32));
      expect(latencyRoundTimeoutFor(20), const Duration(seconds: 32));
      expect(latencyRoundTimeoutFor(21), const Duration(seconds: 47));
      expect(latencyRoundTimeoutFor(25), const Duration(seconds: 47));
      expect(latencyRoundTimeoutFor(31), const Duration(seconds: 60));
      expect(latencyRoundTimeoutFor(5000), const Duration(seconds: 60));
      expect(kLatencyRoundTimeout, latencyRoundTimeoutFor(1));
    });

    for (final (n, budget) in [(10, 17), (11, 32)]) {
      _fake('批次边界：$n 个节点全是死的，恰好等 $budget s 才判失败', (rig, async) {
        rig.urlTestResult = () => Completer<void>().future;
        final dead = {for (var i = 0; i < n; i++) 'n$i': 0};
        rig.groups = [_group(dead)];
        rig.coordinator.onConnectionChanged(true);
        unawaited(rig.coordinator.manualTest('proxy'));

        rig.elapse(Duration(seconds: budget) - const Duration(milliseconds: 1));
        expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
        expect(rig.coordinator.state.timedOutNodes, isEmpty);
        rig.elapse(const Duration(milliseconds: 1));
        expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
        expect(rig.coordinator.state.timedOutNodes, dead.keys.toSet());
        expect(rig.failed.single.$1, dead.keys.toSet());
      });
    }

    _fake('前两批被死节点占满、末批可达：末批的值在第 31 s 到，必须拿到值而不是超时', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      final all = {for (var i = 0; i < 25; i++) 'n$i': 0};
      rig.groups = [_group(all)];
      rig.coordinator.onConnectionChanged(true);
      unawaited(rig.coordinator.manualTest('proxy'));

      // n0..n19 是死节点：前两批各占满 15 s；n20..n24 在第三批，30 s 后才开始，
      // 第 31 s 测出结果。
      rig.elapse(const Duration(seconds: 31));
      rig.push([
        _group({...all, for (var i = 20; i < 25; i++) 'n$i': 100 + i}),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
      expect(rig.coordinator.state.pendingNodes['proxy'], {
        for (var i = 0; i < 20; i++) 'n$i',
      });
      expect(rig.recorded, isEmpty, reason: '还没收尾');

      // 预算是 47 s：到点前一刻仍在等，到点才把死节点判失败。
      rig.elapse(const Duration(seconds: 15, milliseconds: 999));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
      rig.elapse(const Duration(milliseconds: 1));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.recorded.single.$1, {
        for (var i = 20; i < 25; i++) 'n$i': 100 + i,
      });
      expect(rig.coordinator.state.timedOutNodes, {
        for (var i = 0; i < 20; i++) 'n$i',
      });
      expect(
        rig.cache['n20'],
        CachedDelay(120, _t0.add(const Duration(seconds: 47))),
      );
      expect(rig.cache['n0']!.isFailed, isTrue);
    });

    _fake('封顶：节点再多一轮也只等 60 s', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      final dead = {for (var i = 0; i < 100; i++) 'n$i': 0};
      rig.groups = [_group(dead)];
      rig.coordinator.onConnectionChanged(true);
      unawaited(rig.coordinator.manualTest('proxy'));

      rig.elapse(const Duration(seconds: 59, milliseconds: 999));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isTrue);
      rig.elapse(const Duration(milliseconds: 1));
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      expect(rig.coordinator.state.timedOutNodes, dead.keys.toSet());
    });

    // ---- 迟到失败：收尾时标成历史值的节点，之后才失败 ----

    _fake('收尾时历史值、之后实时值有效→0：改记超时并写失败，缓存的旧成功值被覆盖', (rig, async) {
      final at = _t0.subtract(const Duration(minutes: 1));
      rig.cache['a'] = CachedDelay(98, at);
      rig.cache['b'] = CachedDelay(120, at);
      rig.groups = [
        _group({'a': 98, 'b': 120}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(2));
      expect(rig.coordinator.state.unconfirmedNodes, {'a', 'b'});
      expect(rig.failed, isEmpty);
      expect(rig.coordinator.state.isTesting, isFalse, reason: '这一轮已经没了');

      // 内核第 N 秒才测完 a，失败：历史被删，实时值变 0。
      rig.elapse(const Duration(seconds: 5));
      rig.push([
        _group({'a': 0, 'b': 120}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.coordinator.state.unconfirmedNodes, {'b'});
      expect(rig.failed.single.$1, {'a'});
      expect(rig.cache['a']!.isFailed, isTrue);
      expect(rig.cache['b'], CachedDelay(120, at));

      // 同一个失败不重复写。
      rig.push([
        _group({'a': 0, 'b': 120}),
      ]);
      expect(rig.failed, hasLength(1));
    });

    _fake('超过 60 s 封顶才失败的节点同样记成超时并落盘', (rig, async) {
      rig.cache['slow'] = CachedDelay(98, _t0);
      final nodes = {for (var i = 0; i < 100; i++) 'n$i': 90};
      rig.groups = [
        _group({...nodes, 'slow': 98}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(const Duration(seconds: 60));
      expect(rig.coordinator.state.unconfirmedNodes, contains('slow'));

      rig.elapse(const Duration(seconds: 30));
      rig.push([
        _group({...nodes, 'slow': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'slow'});
      expect(rig.failed.single.$1, {'slow'});
      expect(rig.cache['slow']!.isFailed, isTrue);
    });

    _fake('迟到失败之后又测通：成功值照常记，超时标记撤掉', (rig, async) {
      rig.cache['a'] = CachedDelay(98, _t0);
      rig.groups = [
        _group({'a': 98}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(1));
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      rig.push([
        _group({'a': 140}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
    });

    // ---- 真机「阿根廷-边缘节点」：一轮之后、没有任何在途轮次时，节点的实时值
    // 从有效变成 0（内核自己的后台检测测失败、删了测速历史）。这是失败，不是
    // 「没测过」，必须记成超时并落盘；否则它既不在超时集合里、缓存里也没有失败
    // 记录，线路页就稳定显示「—」。 ----

    _fake('一轮里测通、之后（没有在途轮次）内核后台检测测失败：记成超时并写失败', (rig, async) {
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 300, 'b': 120}),
      ]);
      expect(rig.coordinator.state.isTesting, isFalse);
      expect(
        rig.cache['a'],
        CachedDelay(300, _t0.add(const Duration(seconds: 2))),
      );
      expect(rig.coordinator.state.timedOutNodes, isEmpty);

      // 10 分钟后自动选择组的后台检测：a 这次没通。
      rig.elapse(const Duration(minutes: 10));
      rig.push([
        _group({'a': 0, 'b': 120}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.failed.single.$1, {'a'});
      expect(rig.cache['a']!.isFailed, isTrue);
      expect(rig.cache['b']!.ms, 120);

      // 同一个失败不重复写；之后又测通则恢复。
      rig.push([
        _group({'a': 0, 'b': 120}),
      ]);
      expect(rig.failed, hasLength(1));
      rig.push([
        _group({'a': 210, 'b': 120}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('收尾时已判超时的节点偶尔测通一次、随后又失败：重新记成超时并写失败', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(1));
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.failed, hasLength(1));

      rig.push([
        _group({'a': 400}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      // 页面把这次有效值写进缓存（覆盖失败记录）。
      rig.cache['a'] = CachedDelay(400, _t0.add(async.elapsed));

      rig.elapse(const Duration(minutes: 10));
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.failed, hasLength(2));
      expect(rig.cache['a']!.isFailed, isTrue);
    });

    _fake('没有任何轮次：自动选择组后台测通又测失败的节点同样记成超时', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      // 还没到预热：没有在途轮次。
      rig.push([
        _group({'a': 250}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.failed.single.$1, {'a'});
    });

    _fake('断开重连 / 分组流中途清空：历史被清掉的 0 不是失败', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.push([
        _group({'a': 250}),
      ]);
      // 分组流空了一下，再回来时内核换了实例：全是 0。
      rig.push(const []);
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.failed, isEmpty);

      // 断开再连上：同样从头算。
      rig.push([
        _group({'a': 250}),
      ]);
      rig.coordinator.onConnectionChanged(false);
      rig.coordinator.onConnectionChanged(true);
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.failed, isEmpty);
    });

    _fake('内核调用失败的一轮：已知的失败（缓存里有失败记录）不被抹掉，也不重复写', (rig, async) {
      rig.groups = [
        _group({'dead': 0, 'slow': 120}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(2));
      expect(rig.coordinator.state.timedOutNodes, {'dead'});
      final failedBefore = rig.failed.length;

      rig.urlTestResult = () async => throw StateError('kernel down');
      unawaited(
        rig.coordinator.manualTest('proxy').then((_) {}, onError: (_) {}),
      );
      async.flushMicrotasks();
      expect(rig.coordinator.state.isTesting, isFalse);
      expect(rig.coordinator.state.timedOutNodes, {'dead'});
      expect(rig.failed, hasLength(failedBefore));

      // 之后 dead 测通：标记照常撤掉。
      rig.push([
        _group({'dead': 90, 'slow': 120}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('错误轮次不覆盖别的轮次较新的判定：共享节点之后测回旧值也能撤标记，超时与未确认互斥', (rig, async) {
      final kernel = Completer<void>();
      rig.urlTestResult = () => kernel.future;
      rig.groups = [
        _group({'x': 100, 'y': 0}, tag: 'g1'),
        _group({'x': 100}, tag: 'g2'),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(2));
      expect(rig.coordinator.state.unconfirmedNodes, {'x'});

      // g1、g2 同时重测；x 变 0：g2 收尾（x 判超时），g1 还在等 y。
      unawaited(rig.coordinator.manualTest('g1').then((_) {}, onError: (_) {}));
      unawaited(rig.coordinator.manualTest('g2').then((_) {}, onError: (_) {}));
      rig.push([
        _group({'x': 0, 'y': 0}, tag: 'g1'),
        _group({'x': 0}, tag: 'g2'),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'x'});
      expect(rig.coordinator.state.isGroupTesting('g1'), isTrue);

      // g1 的内核调用报错。
      kernel.completeError(StateError('kernel down'));
      async.flushMicrotasks();
      expect(rig.coordinator.state.isTesting, isFalse);
      // y 上一轮就判了超时、缓存里有失败记录：重新标回，不重复写。
      expect(rig.coordinator.state.timedOutNodes, {'x', 'y'});
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);

      // x 又测出 100（恰好与最早那次标记同值）：必须能撤掉超时。
      rig.push([
        _group({'x': 100, 'y': 0}, tag: 'g1'),
        _group({'x': 100}, tag: 'g2'),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'y'});
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
    });

    _fake('带历史标记的节点遇到分组流清空：回来时的 0 不是迟到失败', (rig, async) {
      rig.groups = [
        _group({'a': 120}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(1));
      expect(rig.coordinator.state.unconfirmedNodes, {'a'});

      rig.push(const []);
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
      expect(rig.failed, isEmpty);
    });

    // ---- 在途轮次遇到分组流清空：旧基线与旧确认一并作废 ----

    /// x=120、y=0 开测 → x=130（确认，等 y）→ 分组流清空 → 回来 x=0、y=0。
    Completer<void> clearedMidRound(_Rig rig, FakeAsync async) {
      final kernel = Completer<void>();
      rig.urlTestResult = () => kernel.future;
      rig.groups = [
        _group({'x': 120, 'y': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'x': 130, 'y': 0}),
      ]);
      expect(rig.coordinator.state.pendingNodes['proxy'], {'y'});
      rig.push(const []);
      rig.push([
        _group({'x': 0, 'y': 0}),
      ]);
      // 回来的 0 不是本轮的结果：两个都还在等。
      expect(rig.coordinator.state.pendingNodes['proxy'], {'x', 'y'});
      return kernel;
    }

    _fake('在途 -> 清空 -> 返回 0 -> 旧调用报错：回来的 0 不判失败', (rig, async) {
      final kernel = clearedMidRound(rig, async);
      kernel.completeError(StateError('kernel down'));
      async.flushMicrotasks();
      expect(rig.coordinator.state.isTesting, isFalse);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      expect(rig.failed, isEmpty);
    });

    _fake('在途 -> 清空 -> 返回 0 -> 预算到点：本轮没测出结果，按到点规则判超时', (rig, async) {
      clearedMidRound(rig, async);
      rig.elapse(latencyRoundTimeoutFor(2));
      expect(rig.coordinator.state.timedOutNodes, {'x', 'y'});
    });

    _fake('在途 -> 清空 -> 返回有效值：确认为新结果', (rig, async) {
      clearedMidRound(rig, async);
      rig.push([
        _group({'x': 0, 'y': 80}),
      ]);
      expect(rig.coordinator.state.pendingNodes['proxy'], {'x'});
      rig.push([
        _group({'x': 120, 'y': 80}),
      ]);
      expect(rig.coordinator.state.isTesting, isFalse);
      expect(rig.recorded.single.$1, {'x': 120, 'y': 80});
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('在途轮次里已确认的失败：内核调用报错的异常收尾也要保留（超时 + 写失败）', (rig, async) {
      final kernel = Completer<void>();
      rig.urlTestResult = () => kernel.future;
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 3786, 'b': 0}),
      ]);
      rig.push([
        _group({'a': 0, 'b': 0}),
      ]);
      expect(rig.failed, isEmpty);

      kernel.completeError(StateError('kernel down'));
      async.flushMicrotasks();
      expect(rig.coordinator.state.isTesting, isFalse);
      // a 本轮测出过有效值、随后失败：已观察到的失败；b 还没有任何结果：不判。
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      expect(rig.failed.single.$1, {'a'});
      expect(rig.cache['a']!.isFailed, isTrue);
      expect(rig.cache.containsKey('b'), isFalse);

      // 之后一直是 0，没有新的转变，也保持超时。
      rig.push([
        _group({'a': 0, 'b': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
    });

    _fake('在途轮次里的节点：有效变 0 由收尾判定，不提前记失败', (rig, async) {
      rig.urlTestResult = () => Completer<void>().future;
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 200, 'b': 0}),
      ]);
      rig.push([
        _group({'a': 0, 'b': 0}),
      ]);
      expect(rig.failed, isEmpty);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
      rig.elapse(latencyRoundTimeoutFor(2));
      expect(rig.coordinator.state.timedOutNodes, {'a', 'b'});
    });

    _fake('超时标记之后实时值在 0 与超时哨兵之间来回：仍是超时，不撤标记', (rig, async) {
      rig.groups = [
        _group({'a': 65535}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(latencyRoundTimeoutFor(1));
      expect(rig.coordinator.state.timedOutNodes, {'a'});

      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      rig.push([
        _group({'a': 65535}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      rig.push([
        _group({'a': 0}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, {'a'});
      rig.push([
        _group({'a': 180}),
      ]);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('确认是累积的：先出结果的节点不会因为后续事件变回没结果', (rig, async) {
      rig.groups = [
        _group({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        _group({'a': 120, 'b': 0}),
      ]);
      expect(rig.coordinator.state.pendingNodes['proxy'], {'b'});
      rig.push([
        _group({'a': 0, 'b': 300}),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
      // a 确认过但现在没有有效值：标超时；b 有效：写缓存。
      expect(rig.recorded.single.$1, {'b': 300});
      expect(rig.coordinator.state.timedOutNodes, {'a'});
    });

    _fake('标记之后实时值变了（出了新结果）：撤掉未确认 / 超时标记', (rig, async) {
      rig.groups = [
        _group({'a': 100, 'b': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(kLatencyWarmupDelay + kLatencyRoundTimeout);
      expect(rig.coordinator.state.unconfirmedNodes, {'a'});
      expect(rig.coordinator.state.timedOutNodes, {'b'});

      rig.push([
        _group({'a': 100, 'b': 0}),
      ]);
      expect(rig.coordinator.state.unconfirmedNodes, {'a'}, reason: '值没变，标记保留');
      expect(rig.coordinator.state.timedOutNodes, {'b'});

      rig.push([
        _group({'a': 95, 'b': 210}),
      ]);
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('新一轮开始时清掉上一轮的未确认标记', (rig, async) {
      rig.groups = [
        _group({'a': 100}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(kLatencyWarmupDelay + kLatencyRoundTimeout);
      expect(rig.coordinator.state.unconfirmedNodes, {'a'});
      unawaited(rig.coordinator.manualTest('proxy'));
      expect(rig.coordinator.state.unconfirmedNodes, isEmpty);
    });

    _fake('新一轮开始时清掉上一轮的超时标记', (rig, async) {
      rig.groups = [
        _group({'a': 0}),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.elapse(kLatencyRoundTimeout);
      expect(rig.coordinator.state.timedOutNodes, {'a'});

      unawaited(rig.coordinator.manualTest('proxy'));
      expect(rig.coordinator.state.timedOutNodes, isEmpty);
    });

    _fake('隐藏节点（§hide§）与嵌套分组不参与「是否全部有结果」', (rig, async) {
      rig.groups = [
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'a',
          items: [
            OutboundProxy(tag: 'a', type: 'vmess'),
            OutboundProxy(tag: 'x §hide§', type: 'vmess'),
            OutboundProxy(tag: 'Auto', type: 'urltest'),
          ],
        ),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'a',
          items: [
            OutboundProxy(tag: 'a', type: 'vmess', delay: 90),
            OutboundProxy(tag: 'x §hide§', type: 'vmess'),
            OutboundProxy(tag: 'Auto', type: 'urltest'),
          ],
        ),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
    });
    _fake('构建器隐藏的订阅信息条目不参与「是否全部有结果」（内核不测它）', (rig, async) {
      rig.groups = [
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'a',
          items: [
            OutboundProxy(tag: 'a', type: 'vmess'),
            OutboundProxy(tag: '🌐 官网地址：ncink.cc §hide§', type: 'vmess'),
          ],
        ),
      ];
      rig.coordinator.onConnectionChanged(true);
      rig.elapse(const Duration(seconds: 2));
      rig.push([
        const OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'a',
          items: [
            OutboundProxy(tag: 'a', type: 'vmess', delay: 90),
            OutboundProxy(tag: '🌐 官网地址：ncink.cc §hide§', type: 'vmess'),
          ],
        ),
      ]);
      expect(rig.coordinator.state.isGroupTesting('proxy'), isFalse);
    });
  });

  group('打开代理页时的触发', () {
    OutboundGroup g(Map<String, int> d) => _group(d);

    _fake('已连接且该组没有任何数据：测一次', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.groups = [
        g({'a': 0, 'b': 0}),
      ];
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, ['proxy']);
    });

    _fake('有数据且新鲜（5 分钟内）：不测', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.groups = [
        g({'a': 100}),
      ];
      rig.cache['a'] = CachedDelay(
        100,
        _t0.subtract(const Duration(minutes: 4)),
      );
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, isEmpty);
    });

    _fake('有数据但已超过 5 分钟：测一次', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.groups = [
        g({'a': 100}),
      ];
      rig.cache['a'] = CachedDelay(
        100,
        _t0.subtract(const Duration(minutes: 6)),
      );
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, ['proxy']);
    });

    _fake('历史值（无测量时间）视为过期：测一次', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.groups = [
        g({'a': 100}),
      ];
      rig.cache['a'] = const CachedDelay(100, null);
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, ['proxy']);
    });

    _fake('未连接：不测', (rig, async) {
      rig.groups = [
        g({'a': 0}),
      ];
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, isEmpty);
    });

    _fake('反复打开页面也受 30 s 去重约束', (rig, async) {
      rig.coordinator.onConnectionChanged(true);
      rig.groups = [
        g({'a': 0}),
      ];
      rig.coordinator.onProxiesPageOpened();
      rig.elapse(kLatencyRoundTimeout);
      rig.coordinator.onProxiesPageOpened();
      expect(rig.urlTests, hasLength(1));
    });
  });

  group('Riverpod 接线', () {
    final connected = StateProvider<bool>((_) => false);
    final profileId = StateProvider<String>((_) => 'p1');

    test('连接状态驱动预热与取消；切订阅取消在途任务', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final urlTests = <String>[];
      final groupsController = StreamController<List<OutboundGroup>>();
      addTearDown(groupsController.close);

      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
            activeProfileProvider.overrideWith(
              (ref) async => ProfileEntity(
                id: ref.watch(profileId),
                name: 'x',
                url: 'https://example.com/x',
                active: true,
              ),
            ),
            boxServiceProvider.overrideWithValue(_RecordingBox(urlTests)),
            isConnectedProvider.overrideWith((ref) => ref.watch(connected)),
            outboundGroupsProvider.overrideWith(
              (ref) => groupsController.stream,
            ),
          ],
        );
        container.listen(latencyTestCoordinatorProvider, (_, _) {});
        container.listen(activeProfileProvider, (_, _) {});
        async.flushMicrotasks();

        container.read(connected.notifier).state = true;
        groupsController.add([
          _group({'a': 0}),
        ]);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(urlTests, ['proxy']);
        expect(
          container
              .read(latencyTestCoordinatorProvider)
              .isGroupTesting('proxy'),
          isTrue,
        );

        container.read(profileId.notifier).state = 'p2';
        async.elapse(const Duration(milliseconds: 1));
        expect(
          container.read(latencyTestCoordinatorProvider).testingGroups,
          isEmpty,
          reason: '切订阅取消旧任务',
        );

        container.read(connected.notifier).state = false;
        async.elapse(const Duration(minutes: 1));
        expect(urlTests, ['proxy'], reason: '断开后不会再冒出新的测速');
        container.dispose();
      });
    });
  });
}

class _RecordingBox extends FakeBoxService {
  _RecordingBox(this.urlTests);
  final List<String> urlTests;

  @override
  Future<void> urlTest(String groupTag) async => urlTests.add(groupTag);

  @override
  Stream<BoxStatus> watchStatus() => const Stream.empty();
}
