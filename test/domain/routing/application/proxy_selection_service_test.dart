import 'dart:async';

import 'package:clashmiao/core/box_service/kernel_port.dart';
import 'package:clashmiao/core/box_service/kernel_port_provider.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_service.dart';
import 'package:clashmiao/domain/routing/application/proxy_selection_store_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../_fakes/fake_kernel_port.dart';
import '../../../support/profile_store_support.dart';

final _activeId = StateProvider<String>((_) => 'p1');

void main() {
  late FakeKernelPort port;
  late ProviderContainer container;
  late SharedPreferences prefs;

  Map<String, String> store() => container.read(proxySelectionStoreProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'proxy_selection_p1': '{"proxy":"old","auto":"keep"}',
    });
    prefs = await SharedPreferences.getInstance();
    // 手选写入经 ProfileStore.writeAux 校验订阅存在：p1 / p2 都种进去。
    final profiles = await seededProfileStore(prefs, [
      for (final id in ['p1', 'p2'])
        ProfileEntity(
          id: id,
          name: id,
          url: 'https://example.invalid/$id',
          active: id == 'p1',
        ),
    ]);
    port = FakeKernelPort(
      initial: FakeKernelPort.snap(
        status: KernelStatus.started,
        attempt: 3,
        desired: Desired.on,
      ),
    );
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        profileStoreProvider.overrideWith((_) => Future.value(profiles)),
        kernelPortProvider.overrideWithValue(port),
        activeProfileProvider.overrideWith((ref) async {
          final id = ref.watch(_activeId);
          return ProfileEntity(
            id: id,
            name: id,
            url: 'https://example.invalid/$id',
            active: true,
          );
        }),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileStoreProvider.future);
    await container.read(activeProfileProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await port.dispose();
  });

  ProxySelectionService service() =>
      container.read(proxySelectionServiceProvider);

  test('成功：带 expectedAttempt 调内核，选择写入存储与磁盘', () async {
    final r = await service().select('proxy', 'hk', expectedAttempt: 3);

    expect(r, isA<SelectionApplied>());
    expect(port.selectCalls, [(group: 'proxy', tag: 'hk', expectedAttempt: 3)]);
    expect(store(), {'proxy': 'hk', 'auto': 'keep'});
    expect(prefs.getString('proxy_selection_p1'), contains('"proxy":"hk"'));
  });

  test('先写存储再等内核：内核调用悬停期间存储里已经是新选择', () async {
    final gate = Completer<void>();
    port.onSelectGate = gate;

    final f = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();

    expect(store()['proxy'], 'hk', reason: '重放读取存储时必须看到用户的最新选择');
    gate.complete();
    expect(await f, isA<SelectionApplied>());
  });

  test('失败（非 stale）：存储回滚为点击前的值——失败不持久化', () async {
    port.selectResult = (_, _, _) => const SelectFailed('boom', 'x');

    final r = await service().select('proxy', 'hk', expectedAttempt: 3);

    expect(r, isA<SelectionFailed>());
    expect(store(), {'proxy': 'old', 'auto': 'keep'});
    expect(prefs.getString('proxy_selection_p1'), contains('"proxy":"old"'));
  });

  test('失败且点击前该组没有记录：回滚为「无记录」', () async {
    port.selectResult = (_, _, _) => const SelectFailed('boom');

    await service().select('fresh', 'jp', expectedAttempt: 3);

    expect(store().containsKey('fresh'), isFalse);
    expect(prefs.getString('proxy_selection_p1'), isNot(contains('fresh')));
  });

  test('失败时若用户期间又选了别的：旧调用失败、新调用成功，不回滚', () async {
    final gate = Completer<void>();
    // 结果在调用进入时就固定：hk 失败、sg 成功。
    port.selectResult = (g, t, _) =>
        t == 'hk' ? const SelectFailed('boom') : const SelectOk();

    port.onSelectGate = gate;
    final first = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    port.onSelectGate = null;
    final second = service().select('proxy', 'sg', expectedAttempt: 3);
    expect(await second, isA<SelectionApplied>());
    gate.complete();
    expect(await first, isA<SelectionFailed>());

    expect(store()['proxy'], 'sg', reason: '更新的意图不能被旧失败回滚');
  });

  test('stale：不回滚；内核仍在运行但 attempt 已变 → 用权威 attempt 重试一次', () async {
    port.selectResult = (_, _, attempt) =>
        attempt == 3 ? const SelectStale() : const SelectOk();
    port.push(
      FakeKernelPort.snap(
        version: 2,
        status: KernelStatus.started,
        attempt: 4,
        desired: Desired.on,
      ),
    );

    final r = await service().select('proxy', 'hk', expectedAttempt: 3);

    expect(r, isA<SelectionApplied>());
    expect(port.selectCalls.map((c) => c.expectedAttempt), [3, 4]);
    expect(store()['proxy'], 'hk');
  });

  test('stale 且内核已不在运行 / attempt 没变：保留存储，交给下一个 attempt 的重放', () async {
    port.selectResult = (_, _, _) => const SelectStale();
    port.push(
      FakeKernelPort.snap(
        version: 2,
        status: KernelStatus.starting,
        attempt: 4,
        desired: Desired.on,
      ),
    );

    final r = await service().select('proxy', 'hk', expectedAttempt: 3);

    expect(r, isA<SelectionDeferred>());
    expect(port.selectCalls, hasLength(1));
    expect(store()['proxy'], 'hk', reason: 'stale 不是失败：用户意图留给重放');
  });

  test('端口抛异常也按失败回滚，不向上抛', () async {
    port.selectResult = (_, _, _) => throw StateError('bridge');

    final r = await service().select('proxy', 'hk', expectedAttempt: 3);

    expect(r, isA<SelectionFailed>());
    expect(store()['proxy'], 'old');
  });

  test('stale 后等待权威 attempt 期间用户在新 attempt 选了别的：旧意图被丢弃，不覆盖新选择', () async {
    // A 在旧 attempt(3) 上收到 stale；它去问内核当前 attempt 的那一步悬停。
    port.selectResult = (_, tag, attempt) =>
        tag == 'hk' && attempt == 3 ? const SelectStale() : const SelectOk();
    port.push(
      FakeKernelPort.snap(
        version: 2,
        status: KernelStatus.started,
        attempt: 4,
        desired: Desired.on,
      ),
    );
    final gate = Completer<void>();
    port.currentGate = gate;

    final a = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    expect(port.currentCalls, 1, reason: '前提：A 正悬停在读取权威 attempt');

    // 用户在新 attempt 里选了 sg，成功。
    final b = await service().select('proxy', 'sg', expectedAttempt: 4);
    expect(b, isA<SelectionApplied>());

    gate.complete();
    final ra = await a;

    expect(ra, isA<SelectionSuperseded>());
    expect(
      port.selectCalls.map((c) => (c.tag, c.expectedAttempt)),
      [('hk', 3), ('sg', 4)],
      reason: 'A 不得再带着 hk 重试：否则内核最终是 hk、存储却是 sg',
    );
    expect(store()['proxy'], 'sg');
  });

  test('旧意图失败、更新的意图选了同一个节点且成功：不回滚', () async {
    final gate = Completer<void>();
    var calls = 0;
    // 第 1 次调用（旧意图）进入即固定为失败，第 2 次固定为成功。
    port.selectResult = (_, _, _) =>
        ++calls == 1 ? const SelectFailed('boom') : const SelectOk();

    port.onSelectGate = gate;
    final first = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    port.onSelectGate = null;
    final second = service().select('proxy', 'hk', expectedAttempt: 3);
    expect(await second, isA<SelectionApplied>());
    gate.complete();
    expect(await first, isA<SelectionFailed>());

    expect(store()['proxy'], 'hk', reason: '更新的意图也选了 hk 且成功，旧失败不能把它回滚');
  });

  test('stale 后等待权威 attempt 期间切换了订阅：旧订阅的选择不得对新订阅重试', () async {
    // p1 的 hk 在旧 attempt(3) 上 stale，去问内核权威 attempt 时悬停。
    port.selectResult = (_, tag, attempt) =>
        tag == 'hk' && attempt == 3 ? const SelectStale() : const SelectOk();
    port.push(
      FakeKernelPort.snap(
        version: 2,
        status: KernelStatus.started,
        attempt: 4,
        desired: Desired.on,
      ),
    );
    final gate = Completer<void>();
    port.currentGate = gate;

    final a = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    expect(port.currentCalls, 1, reason: '前提：旧订阅的选择正悬停在读取权威 attempt');

    // 用户切到 p2（同名组 proxy），并在新 attempt 里选了 sg。
    container.read(_activeId.notifier).state = 'p2';
    await container.read(activeProfileProvider.future);
    await pumpEventQueue();
    final b = await service().select('proxy', 'sg', expectedAttempt: 4);
    expect(b, isA<SelectionApplied>());

    gate.complete();
    final ra = await a;

    expect(ra, isA<SelectionSuperseded>());
    expect(
      port.selectCalls.map((c) => (c.tag, c.expectedAttempt)),
      [('hk', 3), ('sg', 4)],
      reason: '旧订阅的 hk 不得再对新订阅的 attempt 重试：两份订阅可能有同名的组与节点',
    );
    expect(store()['proxy'], 'sg', reason: '当前（p2）订阅的存储就是它最后的选择');
    expect(
      prefs.getString('proxy_selection_p1'),
      contains('"proxy":"hk"'),
      reason: 'p1 自己的存储保持它当时写下的值（stale 不回滚）',
    );
  });
}
