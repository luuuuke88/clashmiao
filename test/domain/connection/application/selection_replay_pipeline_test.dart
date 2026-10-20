import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/connection/application/selection_replay_pipeline.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_service.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/failing_prefs_store.dart';
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

class _Env {
  _Env(this.fa, this.prefs, this.store, this.platform) {
    port = FakeKernelPort();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(store)),
        kernelPortProvider.overrideWithValue(port),
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
        liveGroupsProvider.overrideWith((_) => live.stream),
      ],
    );
    container.read(sharedPreferencesProvider);
    container.read(profileStoreProvider);
    fa.flushMicrotasks();
    container.read(activeProfileProvider);
    fa.flushMicrotasks();
    container.listen(liveGroupsProvider, (_, _) {});
    container.listen(proxySelectionStoreProvider, (_, _) {});
    fa.flushMicrotasks();
  }

  final FakeAsync fa;
  final SharedPreferences prefs;
  final ProfileStore store;

  /// 真实的平台存储层（选择存储 → ProfileStore.writeAux → SharedPreferences →
  /// 这里）：写入可在内存缓存更新之后悬停、失败。
  final FailingPrefsStore platform;
  late final FakeKernelPort port;
  late final ProviderContainer container;
  final live = StreamController<LiveGroups?>.broadcast();
  static final activeId = StateProvider<String>((_) => 'p1');

  /// 测试决定哪个 (epoch, attempt) 是当前运行的内核实例。
  ({String epoch, int attempt}) current = (epoch: 'e1', attempt: 1);

  late final _pipeline = Provider<SelectionReplayPipeline>(
    (ref) => SelectionReplayPipeline(
      ref: ref,
      port: port,
      isCurrentInstance: (e, a) => e == current.epoch && a == current.attempt,
      ownerUnsettled: () => paused,
    ),
  );

  /// 模拟配置变更暂停（归属未定）。
  bool paused = false;

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

  Map<String, String> get memory => container.read(proxySelectionStoreProvider);

  /// 真正落盘的内容（不是 SharedPreferences 的内存缓存）。
  String? disk(String profileId) =>
      platform.disk[ProfileStore.selectionKey(profileId)] as String?;

  /// [profileId] 的选择记录被写（含失败的）多少次。
  int writes(String profileId) => platform.attempts
      .where((k) => k == ProfileStore.selectionKey(profileId))
      .length;

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
    final (platform, prefs) = await FailingPrefsStore.install({
      if (p1.isNotEmpty) ProfileStore.selectionKey('p1'): enc(p1),
      if (p2.isNotEmpty) ProfileStore.selectionKey('p2'): enc(p2),
    });
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
      final e = _Env(fa, prefs, store, platform);
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
    _sim('目标写入失败（真实存储层）：来源保留、不对旧 tag 重放；之后的 attempt 重试成功；再跑一遍什么都不变', (e) {
      e.platform.failKeys = {ProfileStore.selectionKey('p1')};
      final first = e.run(1);
      e.pushGroups(1);
      expect(first, [ReplayPipelineOutcome.acknowledged]);
      expect(e.port.selectCalls, isEmpty, reason: 'proxy 在运行时不存在，select 没有记录');
      expect(e.disk('p1'), '{"proxy":"hk"}', reason: '目标没落盘，来源不能删');
      expect(e.memory, {'proxy': 'hk'}, reason: '仍属本次迁移的内存写入被撤回');

      e.platform.failKeys = {};
      final second = e.run(2);
      e.pushGroups(2);
      expect(second, [ReplayPipelineOutcome.acknowledged]);
      expect(e.disk('p1'), '{"select":"hk"}');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 2),
      ]);

      final writes = e.writes('p1');
      final third = e.run(3);
      e.pushGroups(3);
      expect(third, [ReplayPipelineOutcome.acknowledged]);
      expect(e.writes('p1'), writes, reason: '已迁移：不再写');
      expect(e.disk('p1'), '{"select":"hk"}');
      expect(e.port.selectCalls.last, (
        group: 'select',
        tag: 'hk',
        expectedAttempt: 3,
      ));
      expect(e.port.selectCalls.where((c) => c.group == 'proxy'), isEmpty);
      expect(e.port.acknowledged, [1, 2, 3]);
    }, p1: {'proxy': 'hk'});

    _sim('目标写入在内存更新后悬停、最终失败，期间用户手选 sg：回滚只撤销仍属本次迁移的状态——内存、磁盘、下次重放都保留 sg', (e) {
      final hold = e.platform.holdNext = Completer<void>();
      e.platform.holdKey = ProfileStore.selectionKey('p1');
      e.platform.failHeld = true;
      final first = e.run(1);
      e.pushGroups(1);
      expect(e.memory, {'proxy': 'hk', 'select': 'hk'}, reason: '迁移已改内存、落盘悬停');

      final picked = <SelectionResult>[];
      e.container
          .read(proxySelectionServiceProvider)
          .select('select', 'sg', expectedAttempt: 1)
          .then(picked.add);
      e.fa.flushMicrotasks();
      expect(e.memory, {'proxy': 'hk', 'select': 'sg'});

      hold.complete(); // 迁移那次写入失败
      e.fa.flushMicrotasks();

      expect(first, [ReplayPipelineOutcome.acknowledged]);
      expect(picked, [isA<SelectionApplied>()]);
      expect(e.memory, {'proxy': 'hk', 'select': 'sg'}, reason: '用户的新选择不被回滚');
      expect(
        e.disk('p1'),
        '{"proxy":"hk","select":"sg"}',
        reason: '回滚没有排在用户写入之后覆盖磁盘',
      );
      expect(
        e.port.selectCalls.where((c) => c.tag == 'hk'),
        isEmpty,
        reason: '本次重放发的是 sg',
      );

      final second = e.run(2);
      e.pushGroups(2);
      expect(second, [ReplayPipelineOutcome.acknowledged]);
      expect(e.memory, {'select': 'sg'});
      expect(e.disk('p1'), '{"select":"sg"}', reason: '旧来源被 sg 取代后删除');
      expect(e.port.selectCalls.last, (
        group: 'select',
        tag: 'sg',
        expectedAttempt: 2,
      ));
      expect(e.port.selectCalls.where((c) => c.tag == 'hk'), isEmpty);
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
      '迁移写入悬停期间切换订阅：恢复后不删来源、不碰另一订阅、不重放、不确认，报告归属变化',
      (e) {
        final hold = e.platform.holdNext = Completer<void>();
        e.platform.holdKey = ProfileStore.selectionKey('p1');
        final out = e.run(1);
        e.pushGroups(1);
        expect(e.platform.attempts.last, ProfileStore.selectionKey('p1'));

        e.container.read(_Env.activeId.notifier).state = 'p2';
        e.fa.flushMicrotasks();
        e.fa.elapse(const Duration(milliseconds: 1)); // 让 provider 重建跑完
        e.container.read(activeProfileProvider);
        e.fa.flushMicrotasks();
        hold.complete();
        e.fa.flushMicrotasks();

        expect(out, [ReplayPipelineOutcome.droppedOwnerChanged]);
        expect(e.disk('p2'), '{"proxy":"x"}', reason: '另一订阅的记录一个字都不能动');
        expect(e.disk('p1'), contains('"proxy":"hk"'), reason: '来源只在归属有效时删');
        expect(e.port.selectCalls, isEmpty);
        expect(e.port.acknowledged, isEmpty);
      },
      p1: {'proxy': 'hk'},
      p2: {'proxy': 'x'},
    );

    _sim(
      '等待分组期间切换订阅：立刻醒来，报告归属变化（由调用方按新归属重新调度）',
      (e) {
        final out = e.run(1);
        e.fa.elapse(const Duration(seconds: 1));
        expect(out, isEmpty);

        e.container.read(_Env.activeId.notifier).state = 'p2';
        e.fa.flushMicrotasks();
        e.fa.elapse(const Duration(milliseconds: 1));
        e.container.read(activeProfileProvider);
        e.fa.flushMicrotasks();

        expect(out, [ReplayPipelineOutcome.droppedOwnerChanged]);
        expect(e.port.acknowledged, isEmpty);

        final again = e.run(1); // 同一实例、新归属
        e.pushGroups(1);
        expect(again, [ReplayPipelineOutcome.acknowledged]);
        expect(e.port.selectCalls, [
          (group: 'select', tag: 'sg', expectedAttempt: 1),
        ]);
        expect(e.port.acknowledged, [1]);
      },
      p1: {'select': 'hk'},
      p2: {'select': 'sg'},
    );

    _sim('迁移写入悬停期间重连（新 attempt）：旧流水线丢弃；新 attempt 的流水线完成迁移', (e) {
      final hold = e.platform.holdNext = Completer<void>();
      e.platform.holdKey = ProfileStore.selectionKey('p1');
      final old = e.run(1);
      e.pushGroups(1);

      e.current = (epoch: 'e1', attempt: 2); // 内核已换新实例
      hold.complete();
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

  group('归属未定（配置变更暂停中）', () {
    _sim('暂停期间分组到达：不迁移、不重放、不确认，返回 deferred；暂停解除后重跑完成', (e) {
      final out = e.run(1);
      e.paused = true;
      e.pushGroups(1);
      expect(out, [ReplayPipelineOutcome.deferred]);
      expect(e.disk('p1'), '{"proxy":"hk"}');
      expect(e.port.selectCalls, isEmpty);
      expect(e.port.acknowledged, isEmpty);

      expect(e.run(1), [ReplayPipelineOutcome.deferred], reason: '仍在暂停：一开始就延后');

      e.paused = false;
      final again = e.run(1);
      expect(again, [ReplayPipelineOutcome.acknowledged]);
      expect(e.disk('p1'), '{"select":"hk"}');
      expect(e.port.selectCalls, [
        (group: 'select', tag: 'hk', expectedAttempt: 1),
      ]);
      expect(e.port.acknowledged, [1]);
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
