import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/application/profile_failures.dart';
import 'package:clashmiao/domain/profile/application/profiles_update_scheduler.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/profile_harness.dart';

/// 刷新结果因订阅期间被改动而作废（stale）是预期内的取消，不是失败。
/// 这里逐个验证仓库层的调用方契约：addByUrl 的「已有订阅」路径、updateAll、
/// 定时刷新都把它当成「跳过」，而存储只读则必须让用户看到。
void main() {
  late ProfileHarness h;
  const base = 'http://sub.test';

  setUp(() async {
    h = await ProfileHarness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  Map<String, dynamic> pj(String id, {Map<String, dynamic>? more}) => {
    'id': id,
    'name': 'name-$id',
    'url': '$base/$id',
    'updateInterval': 1,
    'rev': 1,
    ...?more,
  };

  test('isStaleRefresh 只认 stale 异常', () {
    expect(isStaleRefresh(const ProfileUpdateStaleException('a')), isTrue);
    expect(isStaleRefresh(StateError('x')), isFalse);
    expect(isStaleRefresh(const StoreReadOnlyException(9)), isFalse);
  });

  group('addByUrl 命中已有订阅 → 再拉取期间订阅被改动', () {
    test('返回仍存在的订阅，不把预期内的取消报成导入失败', () async {
      final a = await h.repo.addByUrl('$base/a');
      final gate = h.adapter.hold('$base/a');

      // 例如深链 / 剪贴板重复导入同一个 URL，附带新名字。
      final importing = h.repo.addByUrl('$base/a', customName: '新名字');
      await h.adapter.waitForRequests(2);
      // 刷新途中用户在别处把 URL 改了。
      await h.repo.editProfile(a.id, newUrl: '$base/a2');
      gate.complete();

      final result = await importing;

      expect(result.id, a.id);
      expect(h.ids, [a.id]);
      final stored = h.repo.getAll().single;
      expect(stored.name, '新名字', reason: '改名已经落地');
      expect(stored.url, '$base/a2');
      expect(h.strayFiles(), isEmpty);
    });

    test('刷新途中订阅被删除：没有订阅可返回，如实报错', () async {
      final a = await h.repo.addByUrl('$base/a');
      final gate = h.adapter.hold('$base/a');
      final importing = h.repo.addByUrl('$base/a');
      final expectation = expectLater(
        importing,
        throwsA(isA<ProfileUpdateStaleException>()),
      );
      await h.adapter.waitForRequests(2);
      await h.repo.delete(a.id);
      gate.complete();
      await expectation;
    });
  });

  group('updateAll：stale 跳过，不影响其它订阅', () {
    test('某条刷新途中被改 URL：它被跳过，其余照常刷新，不抛', () async {
      await h.seedRaw([pj('a'), pj('b')], activeId: 'a');
      final gate = h.adapter.hold('$base/a');
      final all = h.repo.updateAll();
      await h.adapter.waitForRequests(1);

      await h.repo.editProfile('a', newUrl: '$base/a2');
      gate.complete();
      await all; // 不抛

      final byId = {for (final e in h.repo.getAll()) e.id: e};
      expect(byId['a']!.url, '$base/a2');
      expect(byId['a']!.rev, 2, reason: 'a 的旧结果没落地：rev 只因编辑 +1');
      expect(byId['b']!.rev, 2, reason: 'b 照常刷新');
    });

    test('存储只读：updateAll 不能装作更新成功，要把只读异常抛出去', () async {
      await h.seedRaw([pj('a'), pj('b')], activeId: 'a');
      await h.prefs.setInt(kStorageSchemaKey, kCurrentStorageSchema + 1);
      await expectLater(
        h.repo.updateAll(),
        throwsA(isA<StoreReadOnlyException>()),
      );
    });
  });

  group('定时刷新：stale 被跳过', () {
    test('到期订阅刷新途中被改 URL：不抛、不计入已刷新、不触发回调', () async {
      await h.seedRaw([
        pj('a', more: {'lastUpdate': '2020-01-01T00:00:00.000'}),
      ], activeId: 'a');
      final notified = <List<ProfileEntity>>[];
      final scheduler = ProfileUpdateScheduler(
        repositoryProvider: () async => h.repo,
        now: () => DateTime.utc(2026, 1, 1),
        onChecked: notified.add,
      );
      final gate = h.adapter.hold('$base/a');

      final checking = scheduler.checkAndRefreshDue();
      await h.adapter.waitForRequests(1);
      await h.repo.editProfile('a', newName: '改名');
      gate.complete();
      final refreshed = await checking;

      expect(refreshed, isEmpty);
      expect(notified, isEmpty);
      expect(h.repo.getAll().single.name, '改名');
    });
  });
}
