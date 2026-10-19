import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/selection_replay_pipeline.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/profile_store_support.dart';

/// 运行时分组：内核重建的主选择组 `select` + 自动选择组 `auto`。
const _runtime = [
  OutboundGroup(
    tag: 'select',
    type: 'selector',
    selected: 'auto',
    items: [
      OutboundProxy(tag: 'auto', type: 'urltest'),
      OutboundProxy(tag: 'hk', type: 'vless'),
      OutboundProxy(tag: 'sg', type: 'vless'),
    ],
  ),
  OutboundGroup(
    tag: 'auto',
    type: 'urltest',
    selected: 'sg',
    items: [
      OutboundProxy(tag: 'hk', type: 'vless'),
      OutboundProxy(tag: 'sg', type: 'vless'),
    ],
  ),
];

/// 选择存储写入的控制面（跨 notifier 重建共享）。
class _Ctl {
  bool failPersist = false;
  Completer<void>? persistGate;
  final List<(String, String, String)> persistCalls = [];
}

/// 目标写入可悬停 / 可失败的选择存储。
class _GatedStore extends ProxySelectionStoreNotifier {
  _GatedStore(
    this.ctl, {
    required super.prefs,
    required super.store,
    required super.profileId,
    required super.profileInc,
  });

  final _Ctl ctl;

  @override
  Future<bool> persist(String groupTag, String outboundTag) async {
    ctl.persistCalls.add((profileId ?? '', groupTag, outboundTag));
    final gate = ctl.persistGate;
    if (gate != null) await gate.future;
    if (ctl.failPersist) return false;
    return super.persist(groupTag, outboundTag);
  }
}

class _Env {
  _Env(this.fa, this.prefs, this.store) {
    port = FakeKernelPort();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(store)),
        activeProfileProvider.overrideWith((ref) async {
          final id = ref.watch(activeId);
          final inc = store.view().find(id)!.inc;
          return ProfileEntity(
            id: id,
            name: id,
            url: 'https://example.invalid/$id',
            active: true,
            inc: inc,
          );
        }),
        proxySelectionStoreProvider.overrideWith((ref) {
          final p = ref.watch(activeProfileProvider).valueOrNull;
          return _GatedStore(
            ctl,
            prefs: prefs,
            store: store,
            profileId: p?.id,
            profileInc: p?.inc,
          );
        }),
        liveGroupsProvider.overrideWith((_) => live.stream),
      ],
    );
    container.listen(liveGroupsProvider, (_, _) {});
    container.listen(proxySelectionStoreProvider, (_, _) {});
    container.read(sharedPreferencesProvider);
    container.read(activeProfileProvider);
    fa.flushMicrotasks();
  }

  final FakeAsync fa;
  final SharedPreferences prefs;
  final ProfileStore store;
  late final FakeKernelPort port;
  late final ProviderContainer container;
  final ctl = _Ctl();
  final live = StreamController<LiveGroups?>.broadcast();
  static final activeId = StateProvider<String>((_) => 'p1');

  /// 测试决定哪个 (epoch, attempt) 是当前运行的内核实例。
  ({String epoch, int attempt}) current = (epoch: 'e1', attempt: 1);

  late final _pipeline = Provider<SelectionReplayPipeline>(
    (ref) => SelectionReplayPipeline(
      ref: ref,
      port: port,
      isCurrentInstance: (e, a) => e == current.epoch && a == current.attempt,
    ),
  );

  /// 启动一条流水线；结局写进返回的列表。
  List<ReplayPipelineOutcome> run(int attempt) {
    current = (epoch: 'e1', attempt: attempt);
    final out = <ReplayPipelineOutcome>[];
    container.read(_pipeline).run('e1', attempt).then(out.add);
    fa.flushMicrotasks();
    return out;
  }

  void pushGroups(int attempt, [List<OutboundGroup> groups = _runtime]) {
    live.add(LiveGroups((epoch: 'e1', attempt: attempt), groups));
    fa.flushMicrotasks();
  }

  String? disk(String profileId) =>
      prefs.getString(ProfileStore.selectionKey(profileId));

  void dispose() {
    container.dispose();
    unawaited(live.close());
    fa.flushMicrotasks();
  }
}

void _sim(
  String name,
  void Function(_Env e) body, {
  Map<String, String> p1 = const {},
  Map<String, String> p2 = const {},
}) {
  test(name, () async {
    String enc(Map<String, String> m) =>
        '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';
    SharedPreferences.setMockInitialValues({
      if (p1.isNotEmpty) ProfileStore.selectionKey('p1'): enc(p1),
      if (p2.isNotEmpty) ProfileStore.selectionKey('p2'): enc(p2),
    });
    final prefs = await SharedPreferences.getInstance();
    final seeded = await seededProfileStore(prefs, [
      for (final id in ['p1', 'p2'])
        ProfileEntity(
          id: id,
          name: id,
          url: 'https://example.invalid/$id',
          active: id == 'p1',
        ),
    ]);
    fakeAsync((fa) {
      // 存储的异步锁要建在 fake 区里，否则首个写入调度到真实微任务队列、永远悬停。
      final store = ProfileStore(prefs: prefs, configDir: seeded.configDir);
      final e = _Env(fa, prefs, store);
      try {
        body(e);
      } finally {
        e.dispose();
      }
    });
  });
}

void main() {
  group('迁移：先写后删、失败保留来源、可重试、幂等（评审 Important 1）', () {
    _sim('目标写入失败：来源保留、不对旧 tag 重放；之后的 attempt 重试成功；再跑一遍什么都不变', (e) {
      e.ctl.failPersist = true;
      final first = e.run(1);
      e.pushGroups(1);
      expect(first, [ReplayPipelineOutcome.acknowledged]);
      expect(e.port.selectCalls, isEmpty, reason: 'proxy 在运行时不存在，select 没有记录');
      expect(e.disk('p1'), '{"proxy":"hk"}', reason: '目标没落盘，来源不能删');
      expect(e.container.read(proxySelectionStoreProvider), {'proxy': 'hk'});

      e.ctl.failPersist = false;
      final second = e.run(2);
      e.pushGroups(2);
      expect(second, [ReplayPipelineOutcome.acknowledged]);
      expect(e.disk('p1'), '{"select":"hk"}');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 2),
      ]);

      final writes = e.ctl.persistCalls.length;
      final third = e.run(3);
      e.pushGroups(3);
      expect(third, [ReplayPipelineOutcome.acknowledged]);
      expect(e.ctl.persistCalls, hasLength(writes), reason: '已迁移：不再写');
      expect(e.disk('p1'), '{"select":"hk"}');
      expect(e.port.selectCalls.last, (
        group: 'select',
        tag: 'hk',
        expectedAttempt: 3,
      ));
      expect(e.port.selectCalls.where((c) => c.group == 'proxy'), isEmpty);
      expect(e.port.acknowledged, [1, 2, 3]);
    }, p1: {'proxy': 'hk'});

    _sim('运行时主组已有记录：来源被取代，删除；只重放主组', (e) {
      e.run(1);
      e.pushGroups(1);
      expect(e.disk('p1'), '{"select":"sg"}');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'sg', expectedAttempt: 1),
      ]);
    }, p1: {'proxy': 'hk', 'select': 'sg'});

    _sim('节点不在运行时主组里：迁不过去就保留来源，不重放、不删', (e) {
      e.run(1);
      e.pushGroups(1);
      expect(e.disk('p1'), '{"proxy":"已下线"}');
      expect(e.port.selectCalls, isEmpty);
      expect(e.port.acknowledged, [1]);
    }, p1: {'proxy': '已下线'});
  });

  group('归属：(profileId, inc, epoch, attempt) 过期即丢弃（评审 Important 2）', () {
    _sim(
      '迁移写入悬停期间切换订阅：恢复后不删来源、不碰另一订阅、不重放、不确认',
      (e) {
        final gate = e.ctl.persistGate = Completer<void>();
        final out = e.run(1);
        e.pushGroups(1);
        expect(e.ctl.persistCalls.single, ('p1', 'select', 'hk'));

        e.container.read(_Env.activeId.notifier).state = 'p2';
        e.fa.flushMicrotasks();
        e.fa.elapse(const Duration(milliseconds: 1)); // 让 provider 重建跑完
        e.container.read(activeProfileProvider);
        e.fa.flushMicrotasks();
        gate.complete();
        e.fa.flushMicrotasks();

        expect(out, [ReplayPipelineOutcome.dropped]);
        expect(e.disk('p2'), '{"proxy":"x"}', reason: '另一订阅的记录一个字都不能动');
        expect(e.disk('p1'), contains('"proxy":"hk"'), reason: '来源只在归属有效时删');
        expect(e.port.selectCalls, isEmpty);
        expect(e.port.acknowledged, isEmpty);
      },
      p1: {'proxy': 'hk'},
      p2: {'proxy': 'x'},
    );

    _sim('迁移写入悬停期间重连（新 attempt）：旧流水线丢弃；新 attempt 的流水线完成迁移', (e) {
      final gate = e.ctl.persistGate = Completer<void>();
      final old = e.run(1);
      e.pushGroups(1);

      e.current = (epoch: 'e1', attempt: 2); // 内核已换新实例
      e.ctl.persistGate = null;
      gate.complete();
      e.fa.flushMicrotasks();
      expect(old, [ReplayPipelineOutcome.dropped]);
      expect(e.port.selectCalls, isEmpty);
      expect(e.port.acknowledged, isEmpty);
      expect(e.disk('p1'), contains('"proxy":"hk"'), reason: '过期任务不删来源');

      final fresh = e.run(2);
      e.pushGroups(2);
      expect(fresh, [ReplayPipelineOutcome.acknowledged]);
      expect(e.disk('p1'), '{"select":"hk"}', reason: '迁移幂等：目标已在，删来源');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 2),
      ]);
      expect(e.port.acknowledged, [2]);
    }, p1: {'proxy': 'hk'});
  });

  group('有界等待这个实例的第一份实时分组（评审 Important 4）', () {
    _sim('分组迟到但在上限内：等它；别的实例的分组不算', (e) {
      final out = e.run(2);
      e.pushGroups(1); // 上一个实例迟到的分组
      e.fa.elapse(const Duration(seconds: 4));
      expect(out, isEmpty);
      expect(e.port.selectCalls, isEmpty);

      e.pushGroups(2);
      expect(out, [ReplayPipelineOutcome.acknowledged]);
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 2),
      ]);
    }, p1: {'select': 'hk'});

    _sim('超时：不重放（包括旧 tag）、不迁移，记日志并确认', (e) {
      final out = e.run(1);
      e.fa.elapse(kReplayGroupsWait);
      expect(out, [ReplayPipelineOutcome.acknowledgedWithoutGroups]);
      expect(e.port.selectCalls, isEmpty);
      expect(e.port.acknowledged, [1]);
      expect(e.disk('p1'), '{"proxy":"hk","select":"sg"}');
    }, p1: {'proxy': 'hk', 'select': 'sg'});

    _sim('等待期间实例过期：丢弃，不确认', (e) {
      final out = e.run(1);
      e.current = (epoch: 'e1', attempt: 2);
      e.pushGroups(1);
      expect(out, [ReplayPipelineOutcome.dropped]);
      expect(e.port.acknowledged, isEmpty);
    }, p1: {'select': 'hk'});
  });
}
