import 'dart:convert';

import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/profile_harness.dart';

/// 调研文档 §2 的六个丢更新序列。
///
/// 每个用例都用 [GateAdapter] 把某次刷新的网络请求卡在半空，在这段窗口里做
/// 别的写操作，再放行刷新，最后断言：别的写操作没有被刷新的旧快照覆盖，
/// 已删除的订阅没有复活。旧实现里每一个都会失败。
void main() {
  late ProfileHarness h;
  const base = 'http://sub.test';

  setUp(() async {
    h = await ProfileHarness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  Future<String> add(String name) async =>
      (await h.repo.addByUrl('$base/$name')).id;

  test('序列 1 删除复活：刷新 A 进行中删除 C，C 不会被旧快照写回', () async {
    final a = await add('a');
    final c = await add('c');
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.update(a);
    await h.adapter.waitForRequests(3);

    await h.repo.delete(c);
    gate.complete();
    await pending;

    expect(h.ids, [a], reason: '已删除的订阅不能因为刷新写回旧列表而复活');
    expect(h.configFile(c).existsSync(), isFalse);
    expect(h.strayFiles(), isEmpty);
  });

  test('序列 2 新增丢失：刷新 A 进行中新增 D，D 不会被覆盖掉', () async {
    final a = await add('a');
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.update(a);
    await h.adapter.waitForRequests(2);

    final d = await h.repo.addByContent('ss://abc@h:1#x', name: 'D');
    gate.complete();
    await pending;

    expect(h.ids, [a, d.id], reason: '刷新期间新增的订阅必须保留');
    expect(h.configFile(d.id).existsSync(), isTrue, reason: 'D 的配置文件不能成孤儿');
  });

  test('序列 3 激活回退：刷新 A 进行中切换到 B，激活和 active 标记都停在 B', () async {
    final a = await add('a');
    final b = await add('b');
    expect(h.repo.getActive()?.id, a);
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.update(a);
    await h.adapter.waitForRequests(3);

    await h.repo.setActive(b);
    gate.complete();
    await pending;

    expect(h.repo.getActive()?.id, b);
    final all = {for (final e in h.repo.getAll()) e.id: e.active};
    expect(all, {a: false, b: true}, reason: '`.active` 与激活键必须一致');
    expect(
      h.storedJson.every((j) => !j.containsKey('active')),
      isTrue,
      reason: 'active 不再写进订阅 JSON，激活只有一个真源',
    );
  });

  test('序列 4 整实体覆盖：拿着旧快照保存，不会把旧的 lastUpdate / subInfo 写回', () async {
    h.adapter.headersFor = (url, nth) => {
      'subscription-userinfo': ['upload=$nth;download=0;total=100'],
    };
    final a = await add('a');
    final stale = h.repo.getAll().single; // 详情页打开时拿到的旧快照
    expect(stale.subInfo?.upload, 1);

    // 刷新（比如定时刷新）把 lastUpdate / subInfo 写成了更新的值。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final refreshed = await h.repo.update(a);
    expect(refreshed.subInfo?.upload, 2);

    // 页面此时才保存：旧实现是 `updateProfile(stale.copyWith(...))` 整体替换。
    await h.repo.updateProfile(stale.copyWith(name: '新名字'));

    final now = h.repo.getAll().single;
    expect(now.name, '新名字');
    expect(now.subInfo?.upload, 2, reason: '刷新写入的流量信息不能被旧快照覆盖');
    expect(now.lastUpdate, refreshed.lastUpdate);
    expect(now.lastUpdate!.isAfter(stale.lastUpdate!), isTrue);
  });

  test('序列 5 updateAll 窗口：逐条刷新期间的删除与新增都不丢', () async {
    final a = await add('a');
    final b = await add('b');
    final c = await add('c');
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.updateAll();
    await h.adapter.waitForRequests(4);

    await h.repo.delete(b);
    final d = await h.repo.addByContent('ss://abc@h:1#x', name: 'D');
    gate.complete();
    await pending;

    expect(h.ids, [a, c, d.id]);
    expect(h.configFile(b).existsSync(), isFalse, reason: '被删除的 B 不能因后续刷新而复活');
    expect(h.strayFiles(), isEmpty);
  });

  test('序列 6 同一订阅并发刷新：共享同一次网络请求，结果一致', () async {
    final a = await add('a');
    final gate = h.adapter.hold('$base/a');
    final first = h.repo.update(a); // 例如定时刷新
    await h.adapter.waitForRequests(2);
    final second = h.repo.update(a); // 例如用户手动点刷新
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(h.adapter.countFor('$base/a'), 2, reason: '1 次新增 + 1 次刷新，不是 2 次刷新');
    gate.complete();
    final results = await Future.wait([first, second]);

    expect(results[0].rev, results[1].rev);
    expect(results[0].lastUpdate, results[1].lastUpdate);
    expect(h.repo.getAll().single.rev, 2, reason: '只落地了一次刷新');
    final out =
        jsonDecode(h.configFile(a).readAsStringSync()) as Map<String, dynamic>;
    expect(out['outbounds'], isNotEmpty);
  });

  test('刷新期间被编辑 URL：旧结果被判 stale，不落地', () async {
    final a = await add('a');
    final before = h.configFile(a).readAsStringSync();
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.update(a);
    final expectation = expectLater(
      pending,
      throwsA(isA<ProfileUpdateStaleException>()),
    );
    await h.adapter.waitForRequests(2);

    await h.repo.editProfile(a, newUrl: '$base/a2');
    gate.complete();
    await expectation;

    final cur = h.repo.getAll().single;
    expect(cur.url, '$base/a2');
    expect(
      h.configFile(a).readAsStringSync(),
      before,
      reason: '旧 URL 的内容不能覆盖配置文件',
    );
    expect(h.strayFiles(), isEmpty, reason: '暂存文件要被清掉');
  });

  test('删除后同 id 恢复（新 inc）：删除前发出的旧刷新不会覆盖恢复出来的订阅', () async {
    final a = await add('a');
    final original = h.repo.getAll().single;
    final gate = h.adapter.hold('$base/a');
    final pending = h.repo.update(a);
    final expectation = expectLater(
      pending,
      throwsA(isA<ProfileUpdateStaleException>()),
    );
    await h.adapter.waitForRequests(2);

    // 备份恢复同一个 id，并写回它自己的配置。
    final backupJson = Map<String, dynamic>.from(original.toJson())
      ..remove('inc');
    await h.repo.delete(a);
    await h.repo.upsert(backupJson);
    h.configFile(a).writeAsStringSync('restored-config');
    gate.complete();
    await expectation;

    final restored = h.repo.getAll().single;
    expect(restored.id, a);
    expect(restored.inc, isNot(original.inc), reason: '恢复出来的是新一代对象');
    expect(h.configFile(a).readAsStringSync(), 'restored-config');
  });

  test('同 id 不同输入不共享 in-flight：改了 URL 之后的刷新走自己的请求', () async {
    final a = await add('a');
    final gate = h.adapter.hold('$base/a');
    final first = h.repo.update(a);
    final firstExpectation = expectLater(
      first,
      throwsA(isA<ProfileUpdateStaleException>()),
    );
    await h.adapter.waitForRequests(2);
    expect(h.store.inFlightCount, 1);

    await h.repo.editProfile(a, newUrl: '$base/a2');
    final second = await h.repo.update(a); // 新输入：新请求，不被旧的挡住

    expect(h.adapter.countFor('$base/a2'), 1);
    expect(second.url, '$base/a2');
    expect(h.store.inFlightCount, 1, reason: '旧请求还卡着，新请求已结束并出表');

    gate.complete();
    await firstExpectation;
    expect(h.store.inFlightCount, 0, reason: 'stale 结束同样要出表');
    expect(h.repo.getAll().single.url, '$base/a2');
  });

  test('刷新失败（网络错误）也会出表，之后可以重新刷新', () async {
    final a = await add('a');
    h.adapter.bodyFor = (url, nth) => throw StateError('network down');
    await expectLater(h.repo.update(a), throwsA(anything));
    expect(h.store.inFlightCount, 0);

    h.adapter.bodyFor = null;
    final ok = await h.repo.update(a);
    expect(ok.rev, 2);
  });
}
