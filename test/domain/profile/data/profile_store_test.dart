import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/profile_harness.dart';

Map<String, dynamic> _pj(String id, {Map<String, dynamic>? more}) => {
  'id': id,
  'name': 'name-$id',
  'url': 'http://sub.test/$id',
  'updateInterval': 1,
  'rev': 1,
  ...?more,
};

void main() {
  late ProfileHarness h;

  setUp(() async {
    h = await ProfileHarness.create();
  });

  tearDown(() async {
    await h.dispose();
  });

  Future<ProfileEntity> addContent(String name) =>
      h.repo.addByContent('ss://${name}abc@h:1#$name', name: name);

  group('容错读取：坏数据只影响自己那一条，读取永不抛出', () {
    test('外层 JSON 无法解析：返回空列表；下一次提交前原文被保存，主列表重新可用', () async {
      await h.seedRaw('{not json[');
      expect(h.repo.getAll(), isEmpty);
      expect(h.repo.getActive(), isNull);

      final added = await addContent('A');

      expect(h.prefs.getString(ProfileStore.corruptKey), '{not json[');
      expect(h.ids, [added.id]);
      expect(jsonDecode(h.rawList!), isA<List<dynamic>>());
    });

    test('外层是合法 JSON 但不是数组：同样按损坏处理', () async {
      await h.seedRaw('{"a": 1}');
      expect(h.repo.getAll(), isEmpty);
      await addContent('A');
      expect(h.prefs.getString(ProfileStore.corruptKey), '{"a": 1}');
    });

    test('坏条目（非对象、缺字段、类型错、非法 id、重复 id）进隔离区，好条目照常可用', () async {
      final bad = <Object?>[
        42,
        {'name': '没有 id', 'url': 'http://x'},
        _pj('../x'),
        _pj('a', more: {'name': '重复的 a'}),
        _pj('b', more: {'name': 5}),
      ];
      await h.seedRaw([
        _pj('a'),
        bad[0],
        bad[1],
        bad[2],
        bad[3],
        bad[4],
        _pj('c'),
      ]);

      expect(h.ids, ['a', 'c'], reason: '只剩合法且不重复的条目');

      // 触发一次写回：隔离区落盘，主列表只含合法条目，坏条目不回流。
      final added = await addContent('N');
      expect(h.ids, ['a', 'c', added.id]);
      expect(h.storedJson.map((j) => j['id']), ['a', 'c', added.id]);
      expect(h.rawList, isNot(contains('../x')));

      final quarantined = h.store.readQuarantine();
      expect(quarantined, hasLength(5));
      expect(quarantined, containsAll(bad));

      // 再提交几次：隔离区不重复追加，也不再冒出新条目。
      await h.repo.setActive('c');
      await h.repo.editProfile('a', newName: '改名');
      expect(h.store.readQuarantine(), hasLength(5));
    });

    test('隔离区最多保留最近 50 条', () async {
      await h.seedRaw([
        for (var i = 0; i < 60; i++) {'junk': i},
        _pj('a'),
      ]);
      await addContent('N');
      final q = h.store.readQuarantine();
      expect(q, hasLength(ProfileStore.quarantineLimit));
      expect((q.last! as Map<String, dynamic>)['junk'], 59);
      expect((q.first! as Map<String, dynamic>)['junk'], 10);
    });

    test('删除订阅不影响隔离区', () async {
      await h.seedRaw([_pj('a'), 'junk']);
      await addContent('N');
      expect(h.store.readQuarantine(), ['junk']);
      await h.repo.delete('a');
      expect(h.store.readQuarantine(), ['junk']);
    });

    test('激活键被写成了别的类型：读取不抛，当作没有激活', () async {
      await h.seedRaw([_pj('a')]);
      await h.prefs.setInt(ProfileStore.activeProfileKey, 7);
      expect(h.repo.getAll().map((e) => e.id), ['a']);
      expect(h.repo.getActive(), isNull);
    });

    test('个别字段缺失用默认值，旧数据（无 rev / inc）正常读取', () async {
      await h.seedRaw([
        {'id': 'old', 'name': 'old', 'url': 'http://x', 'active': true},
      ], activeId: 'old');
      final e = h.repo.getAll().single;
      expect(e.rev, 1);
      expect(e.inc, '');
      expect(h.repo.getActive()?.id, 'old');
    });
  });

  group('激活只有一个真源', () {
    test('读取时忽略 JSON 里旧的 active 字段，按激活键计算', () async {
      await h.seedRaw([
        _pj('a', more: {'active': true}),
        _pj('b', more: {'active': true}),
      ], activeId: 'b');
      expect(
        {for (final e in h.repo.getAll()) e.id: e.active},
        {'a': false, 'b': true},
      );
    });

    test('激活键缺失：没有激活项；指向不存在的 id：退到第一条', () async {
      await h.seedRaw([_pj('a'), _pj('b')]);
      expect(h.repo.getActive(), isNull);
      expect(h.repo.getAll().every((e) => !e.active), isTrue);

      await h.prefs.setString(ProfileStore.activeProfileKey, 'ghost');
      expect(h.repo.getActive()?.id, 'a');
      expect(h.repo.getAll().first.active, isTrue);
    });

    test('写回后 JSON 里不再有 active，且旧的 active 字段被清掉', () async {
      await h.seedRaw([
        _pj('a', more: {'active': true}),
      ], activeId: 'a');
      await h.repo.editProfile('a', newName: 'x');
      expect(h.storedJson.single.containsKey('active'), isFalse);
    });

    test('并发新增两条：只有第一条自动激活（首条判断在 plan 内）', () async {
      final results = await Future.wait([addContent('A'), addContent('B')]);
      final active = h.repo.getAll().where((e) => e.active).toList();
      expect(active, hasLength(1));
      expect(h.repo.getActive()?.id, active.single.id);
      expect(results.where((e) => e.active), hasLength(1));
      expect(h.repo.getAll().first.active, isTrue);
    });

    test('并发 addByUrl 同一个 URL：只产生一条订阅（去重判断在 plan 内）', () async {
      final both = await Future.wait([
        h.repo.addByUrl('http://sub.test/same'),
        h.repo.addByUrl('http://sub.test/same'),
      ]);
      expect(h.ids, hasLength(1));
      expect(both[0].id, both[1].id);
      expect(h.strayFiles(), isEmpty);
    });
  });

  group('删除', () {
    test('同一次提交清理配置文件与 proxy_selection / proxy_delays 附属键', () async {
      final a = await addContent('A');
      final b = await addContent('B');
      await h.prefs.setString('proxy_selection_${a.id}', '{"p":"x"}');
      await h.prefs.setString('proxy_delays_${a.id}', '{"x":1}');
      await h.prefs.setString('proxy_selection_${b.id}', '{"p":"y"}');

      await h.repo.delete(a.id);

      expect(h.prefs.getString('proxy_selection_${a.id}'), isNull);
      expect(h.prefs.getString('proxy_delays_${a.id}'), isNull);
      expect(h.prefs.getString('proxy_selection_${b.id}'), '{"p":"y"}');
      expect(h.configFile(a.id).existsSync(), isFalse);
      expect(h.repo.getActive()?.id, b.id, reason: '删的是激活项：切到剩下的第一条');
      expect(h.strayFiles(), isEmpty);
    });

    test('删最后一条：激活键被清掉，而不是留着指向已删除的 id', () async {
      final a = await addContent('A');
      await h.repo.delete(a.id);
      expect(h.prefs.getString(ProfileStore.activeProfileKey), isNull);
      expect(h.repo.getActive(), isNull);
    });

    test('删不存在的 id 是空操作', () async {
      final a = await addContent('A');
      await h.repo.delete('ghost');
      expect(h.ids, [a.id]);
    });
  });

  group('提交失败会还原（setString 返回 false）', () {
    late ProfileHarness f;

    setUp(() async {
      f = await ProfileHarness.create(flaky: true);
    });

    tearDown(() async {
      await f.dispose();
    });

    test('刷新时列表写入失败：配置文件还原为旧内容，列表不变，不留暂存', () async {
      final a = await f.repo.addByUrl('http://sub.test/a');
      final fileBefore = f.configFile(a.id).readAsStringSync();
      final listBefore = f.rawList;
      f.flaky!
        ..failKeys = {ProfileStore.profilesKey}
        ..failuresLeft = 1;

      await expectLater(
        f.repo.update(a.id),
        throwsA(isA<ProfileStorageException>()),
      );

      expect(f.configFile(a.id).readAsStringSync(), fileBefore);
      expect(f.rawList, listBefore);
      expect(f.strayFiles(), isEmpty);
      // 失败不是永久性的：之后可以正常刷新。
      expect((await f.repo.update(a.id)).rev, 2);
    });

    test('删除激活订阅时激活键写入失败：列表、激活、配置文件、附属键全部还原', () async {
      final a = await f.repo.addByContent('ss://a@h:1#a', name: 'A');
      final b = await f.repo.addByContent('ss://b@h:1#b', name: 'B');
      await f.prefs.setString('proxy_selection_${a.id}', '{"p":"x"}');
      final listBefore = f.rawList;
      final configBefore = f.configFile(a.id).readAsStringSync();
      f.flaky!
        ..failKeys = {ProfileStore.activeProfileKey}
        ..failuresLeft = 1;

      await expectLater(
        f.repo.delete(a.id),
        throwsA(isA<ProfileStorageException>()),
      );

      expect(f.rawList, listBefore);
      expect(f.prefs.getString(ProfileStore.activeProfileKey), a.id);
      expect(f.configFile(a.id).readAsStringSync(), configBefore);
      expect(f.prefs.getString('proxy_selection_${a.id}'), '{"p":"x"}');
      expect(f.ids, [a.id, b.id]);
      expect(f.strayFiles(), isEmpty);
    });

    test('新增时列表写入失败：没有留下孤儿配置文件', () async {
      f.flaky!
        ..failKeys = {ProfileStore.profilesKey}
        ..failuresLeft = 1;
      await expectLater(
        f.repo.addByContent('ss://a@h:1#a', name: 'A'),
        throwsA(isA<ProfileStorageException>()),
      );
      expect(f.ids, isEmpty);
      expect(
        f.profilesDir.existsSync()
            ? f.profilesDir.listSync()
            : <FileSystemEntity>[],
        isEmpty,
      );
      expect(f.prefs.getString(ProfileStore.activeProfileKey), isNull);
    });

    test('失败的提交不广播变更，成功的提交广播一次', () async {
      var events = 0;
      final sub = f.store.changes.listen((_) => events++);
      addTearDown(sub.cancel);

      f.flaky!
        ..failKeys = {ProfileStore.profilesKey}
        ..failuresLeft = 1;
      await expectLater(
        f.repo.addByContent('ss://a@h:1#a', name: 'A'),
        throwsA(isA<ProfileStorageException>()),
      );
      await pumpEventQueue();
      expect(events, 0);

      await f.repo.addByContent('ss://a@h:1#a', name: 'A');
      await pumpEventQueue();
      expect(events, 1);
    });
  });

  group('变更通知', () {
    test('每次成功提交广播一次；无变化的提交不广播', () async {
      var events = 0;
      final sub = h.store.changes.listen((_) => events++);
      addTearDown(sub.cancel);

      final a = await addContent('A');
      await pumpEventQueue();
      expect(events, 1);

      await h.repo.setActive(a.id); // 已经是激活项：无变化
      await h.repo.editProfile(a.id, newName: 'A'); // 同名：无变化
      await h.repo.delete('ghost');
      await pumpEventQueue();
      expect(events, 1);

      await h.repo.editProfile(a.id, newName: 'renamed');
      await pumpEventQueue();
      expect(events, 2);
    });
  });

  group('启动清理残留（cleanupResidue）', () {
    File put(String name, [String content = 'x']) {
      h.profilesDir.createSync(recursive: true);
      return File('${h.profilesDir.path}/$name')..writeAsStringSync(content);
    }

    test('未提交的暂存文件及其衍生物被删除，无关文件不动', () async {
      await h.seedRaw([_pj('a')]);
      put('a.json', 'formal');
      put('a.1234.staging');
      put('a.1234.staging.next');
      put('a.1234.staging.tmp');
      put('a.json.next');
      put('a.json.tmp');
      put('notes.txt');

      await h.store.cleanupResidue();

      expect(h.strayFiles(), ['notes.txt']);
      expect(h.configFile('a').readAsStringSync(), 'formal');
    });

    test('正式文件与 .undo 同时存在：保留正式文件（较新的同源内容），删 .undo', () async {
      await h.seedRaw([_pj('a')]);
      put('a.json', 'newer');
      put('a.beef.undo', 'older');
      await h.store.cleanupResidue();
      expect(h.configFile('a').readAsStringSync(), 'newer');
      expect(h.strayFiles(), isEmpty);
    });

    test('正式文件缺失且订阅仍在列表里：从 .undo 还原', () async {
      await h.seedRaw([_pj('a')]);
      put('a.beef.undo', 'saved');
      await h.store.cleanupResidue();
      expect(h.configFile('a').readAsStringSync(), 'saved');
      expect(h.strayFiles(), isEmpty);
    });

    test('订阅已不在列表里（删除已提交、清理前被杀）：.undo 直接删除，不复活孤儿文件', () async {
      await h.seedRaw([_pj('a')]);
      put('gone.beef.undo', 'orphan');
      await h.store.cleanupResidue();
      expect(File('${h.profilesDir.path}/gone.json').existsSync(), isFalse);
      expect(h.strayFiles(), isEmpty);
    });

    test('profiles 目录不存在时安静返回', () async {
      await h.store.cleanupResidue();
    });
  });

  group('降级只读（schema 高于当前版本）', () {
    test('commit 抛 StoreReadOnlyException，读取与附属数据写入照常', () async {
      final a = await addContent('A');
      await h.prefs.setInt(kStorageSchemaKey, kCurrentStorageSchema + 1);
      final listBefore = h.rawList;

      expect(h.store.isReadOnly, isTrue);
      await expectLater(
        h.repo.setActive(a.id),
        throwsA(isA<StoreReadOnlyException>()),
      );
      await expectLater(
        h.repo.addByContent('ss://b@h:1#b', name: 'B'),
        throwsA(isA<StoreReadOnlyException>()),
      );
      await expectLater(
        h.repo.delete(a.id),
        throwsA(isA<StoreReadOnlyException>()),
      );

      expect(h.rawList, listBefore);
      expect(h.ids, [a.id]);
      expect(h.strayFiles(), isEmpty, reason: '被拒绝的新增不能留下暂存文件');
      expect(
        await h.store.writeAux(
          a.id,
          a.inc,
          'proxy_selection_${a.id}',
          '{"p":"x"}',
        ),
        isTrue,
        reason: '其余偏好照常读写',
      );
    });

    test('schema 等于当前版本或类型异常时不是只读', () async {
      await h.prefs.setInt(kStorageSchemaKey, kCurrentStorageSchema);
      expect(h.store.isReadOnly, isFalse);
      await h.prefs.setString(kStorageSchemaKey, 'weird');
      expect(h.store.isReadOnly, isFalse);
      await addContent('A');
    });
  });

  group('writeAux：附属数据只写给同一代的订阅', () {
    test('订阅存在且 inc 一致才写入', () async {
      final a = await addContent('A');
      final key = 'proxy_selection_${a.id}';

      expect(await h.store.writeAux(a.id, a.inc, key, '{"p":"x"}'), isTrue);
      expect(h.prefs.getString(key), '{"p":"x"}');
      expect(await h.store.writeAux(a.id, a.inc, key, null), isTrue);
      expect(h.prefs.getString(key), isNull);
    });

    test('订阅被删除后，旧 notifier 的写入被丢弃，不复活孤儿键', () async {
      final a = await addContent('A');
      final key = 'proxy_delays_${a.id}';
      await h.repo.delete(a.id);

      expect(await h.store.writeAux(a.id, a.inc, key, '{"x":1}'), isFalse);
      expect(h.prefs.getString(key), isNull);
    });

    test('同 id 恢复换代后，旧一代的写入被丢弃', () async {
      final a = await addContent('A');
      final key = 'proxy_selection_${a.id}';
      final json = h.repo.getAll().single.toJson();
      await h.repo.delete(a.id);
      await h.repo.upsert(json);

      expect(await h.store.writeAux(a.id, a.inc, key, '{"p":"old"}'), isFalse);
      final fresh = h.repo.getAll().single;
      expect(fresh.inc, isNot(a.inc));
      expect(
        await h.store.writeAux(a.id, fresh.inc, key, '{"p":"new"}'),
        isTrue,
      );
      expect(h.prefs.getString(key), '{"p":"new"}');
    });

    test('只接受该订阅名下的附属键，其它键一律拒绝', () async {
      final a = await addContent('A');
      expect(
        await h.store.writeAux(a.id, a.inc, 'clashmiao_profiles', '[]'),
        isFalse,
      );
      expect(
        await h.store.writeAux(a.id, a.inc, 'proxy_selection_other', '{}'),
        isFalse,
      );
      expect(h.rawList, isNot('[]'));
    });

    test('v0 老数据（inc 为空）的订阅：空 inc 的写入者照常可写', () async {
      await h.seedRaw([_pj('old')], activeId: 'old');
      expect(
        await h.store.writeAux('old', '', 'proxy_selection_old', '{"p":"x"}'),
        isTrue,
      );
    });
  });

  group('路径安全', () {
    test('configFilePath 对非法 id 抛 ArgumentError', () {
      for (final bad in ['../x', 'a/b', r'a\b', '', 'a.b', 'a b', 'x' * 65]) {
        expect(
          () => h.repo.configFilePath(bad),
          throwsArgumentError,
          reason: '"$bad"',
        );
      }
      expect(
        h.repo.configFilePath('ok_ID-1'),
        endsWith('profiles/ok_ID-1.json'),
      );
    });

    test('合法 id 的边界：64 个字符、下划线、连字符', () {
      expect(ProfileStore.isValidId('a' * 64), isTrue);
      expect(ProfileStore.isValidId('A_b-9'), isTrue);
      expect(ProfileStore.isValidId('a' * 65), isFalse);
    });

    test('upsert / delete / update 面对恶意 id 不会读写 profiles 目录之外的文件', () async {
      final outside = File('${h.tmpDir.path}/evil.json')
        ..writeAsStringSync('precious');

      await expectLater(h.repo.upsert(_pj('../evil')), throwsArgumentError);
      await h.repo.delete('../evil'); // 不存在 → 空操作
      await expectLater(h.repo.update('../evil'), throwsA(isA<Exception>()));

      expect(outside.readAsStringSync(), 'precious');
      expect(h.ids, isEmpty);
    });

    test('plan 里夹带恶意 id 的提交整体被拒绝，什么都没碰', () async {
      final outside = File('${h.tmpDir.path}/evil.json')
        ..writeAsStringSync('precious');
      final a = await addContent('A');
      final listBefore = h.rawList;

      final result = await h.store.commit<void>(
        (view) => const Plan<void>(removedProfileIds: ['../evil']),
      );
      expect(result.isFailed, isTrue);
      final result2 = await h.store.commit<void>(
        (view) => Plan<void>(
          profiles: [
            ...view.profiles,
            view.profiles.first.copyWith(id: '../evil'),
          ],
        ),
      );
      expect(result2.isFailed, isTrue);

      expect(outside.readAsStringSync(), 'precious');
      expect(h.rawList, listBefore);
      expect(h.ids, [a.id]);
    });

    test('偏好里被塞进去的恶意 id 条目被隔离，读不到也写不到', () async {
      final outside = File('${h.tmpDir.path}/evil.json')
        ..writeAsStringSync('precious');
      await h.seedRaw([_pj('../evil'), _pj('good')], activeId: '../evil');

      expect(h.ids, ['good']);
      expect(h.repo.getActive()?.id, 'good', reason: '激活键指向被隔离条目：退到第一条合法的');
      await h.repo.delete('good');
      expect(outside.readAsStringSync(), 'precious');
    });
  });
}
