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
        kernelPortProvider.overrideWithValue(port),
        activeProfileProvider.overrideWith(
          (_) async => const ProfileEntity(
            id: 'p1',
            name: 'P1',
            url: 'https://example.invalid/p1',
            active: true,
          ),
        ),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
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

  test('失败时若用户期间又选了别的：不回滚（更新的意图不能被覆盖）', () async {
    final gate = Completer<void>();
    port.onSelectGate = gate;
    port.selectResult = (g, t, _) =>
        t == 'hk' ? const SelectFailed('boom') : const SelectOk();

    final first = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    port.onSelectGate = null;
    final second = service().select('proxy', 'sg', expectedAttempt: 3);
    gate.complete();
    await Future.wait([first, second]);

    expect(store()['proxy'], 'sg');
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

  test('旧意图失败时若更新的意图选了同一个节点：不回滚', () async {
    final gate = Completer<void>();
    port.onSelectGate = gate;
    var calls = 0;
    // 第一次（旧意图）失败，第二次成功。
    port.selectResult = (_, _, _) =>
        ++calls == 1 ? const SelectFailed('boom') : const SelectOk();

    final first = service().select('proxy', 'hk', expectedAttempt: 3);
    await pumpEventQueue();
    port.onSelectGate = null;
    final second = service().select('proxy', 'hk', expectedAttempt: 3);
    gate.complete();
    await Future.wait([first, second]);

    expect(store()['proxy'], 'hk', reason: '更新的意图也选了 hk 且成功，旧失败不能把它回滚');
  });
}
