import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/migrations/v1_profiles.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../support/crashable_prefs.dart';
import '../../../../support/profile_harness.dart';

const _profiles = ProfileStore.profilesKey;
const _active = ProfileStore.activeProfileKey;

Map<String, dynamic> _p(
  String id, {
  bool? active,
  Map<String, dynamic>? more,
}) => {
  'id': id,
  'name': 'name-$id',
  'url': 'http://sub.test/$id',
  'updateInterval': 1,
  'active': ?active,
  ...?more,
};

/// 每次调用从头开始的确定性 inc 生成器：保证「中断后重跑」与「一次跑完」
/// 在能比较的前提下得到相同的值。
String Function() _incs() {
  var n = 0;
  return () => 'inc${(n++).toString().padLeft(13, '0')}';
}

Future<SharedPreferences> _seed(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(Map.of(initial));
  return SharedPreferences.getInstance();
}

Map<String, Object?> _snapshot(SharedPreferences p) => {
  for (final k in p.getKeys()) k: p.get(k),
};

Future<MigrationReport> _run(SharedPreferences prefs) =>
    StorageMigrator(migrations: [profilesV1Migration(incGenerator: _incs())])
        .run(prefs);

List<Map<String, dynamic>> _list(SharedPreferences p) =>
    (jsonDecode(p.getString(_profiles)!) as List).cast<Map<String, dynamic>>();

Map<String, Object> _v0({
  List<Map<String, dynamic>>? list,
  String? active,
  Map<String, Object> extra = const {},
}) => {
  if (list != null) _profiles: jsonEncode(list),
  _active: ?active,
  ...extra,
};

void main() {
  test('订阅迁移是第 1 步', () {
    expect(profilesV1Migration().toVersion, 1);
  });

  group('v0 → v1 夹具', () {
    test('激活键缺失：取第一个 active=true 的条目；JSON 去掉 active、补 rev 与 inc', () async {
      final prefs = await _seed(
        _v0(
          list: [
            _p('a', active: false),
            _p('b', active: true),
            _p('c', active: true),
          ],
        ),
      );
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.migrated);
      expect(prefs.getString(_active), 'b');
      final list = _list(prefs);
      expect(list.map((e) => e['id']), ['a', 'b', 'c']);
      for (final e in list) {
        expect(e.containsKey('active'), isFalse);
        expect(e['rev'], 1);
        expect(e['inc'], matches(RegExp(r'^inc\d{13}$')));
      }
      expect(list.map((e) => e['inc']).toSet().length, 3, reason: '每条各自一个 inc');
      expect(prefs.getInt(kStorageSchemaKey), 1);
    });

    test('激活键指向不存在的订阅：回落到第一个 active=true', () async {
      final prefs = await _seed(
        _v0(list: [_p('a'), _p('b', active: true)], active: 'ghost'),
      );
      await _run(prefs);
      expect(prefs.getString(_active), 'b');
    });

    test('激活键有效：即使别的条目写着 active=true 也以激活键为准', () async {
      final prefs = await _seed(
        _v0(list: [_p('a', active: true), _p('b')], active: 'b'),
      );
      await _run(prefs);
      expect(prefs.getString(_active), 'b');
    });

    test('没有激活键也没有 active=true：取第一条', () async {
      final prefs = await _seed(_v0(list: [_p('x'), _p('y')]));
      await _run(prefs);
      expect(prefs.getString(_active), 'x');
    });

    test('空列表：激活键被清空，schema 推进', () async {
      final prefs = await _seed(_v0(list: [], active: 'old'));
      await _run(prefs);
      expect(prefs.containsKey(_active), isFalse);
      expect(prefs.getString(_profiles), '[]');
      expect(prefs.getInt(kStorageSchemaKey), 1);
    });

    test('全新安装（什么都没有）：只写 schema，不造出多余的键', () async {
      final prefs = await _seed({'theme_mode': 'dark'});
      await _run(prefs);
      expect(_snapshot(prefs), {'theme_mode': 'dark', kStorageSchemaKey: 1});
    });

    test('孤儿键：不存在订阅的 proxy_selection_* / proxy_delays_* 被删，存在的保留', () async {
      final prefs = await _seed(
        _v0(
          list: [
            _p('a'),
            // 解析不了（缺 url）但 id 看得出来：它的附属键保守保留。
            {'id': 'weird', 'name': 'n'},
          ],
          extra: {
            'proxy_selection_a': '{"g":"n"}',
            'proxy_delays_a': '{}',
            'proxy_selection_gone': 'x',
            'proxy_delays_gone': 'x',
            'proxy_selection_weird': 'keep',
            'unrelated_key': 'keep',
          },
        ),
      );
      await _run(prefs);
      expect(prefs.containsKey('proxy_selection_gone'), isFalse);
      expect(prefs.containsKey('proxy_delays_gone'), isFalse);
      expect(prefs.getString('proxy_selection_a'), '{"g":"n"}');
      expect(prefs.getString('proxy_delays_a'), '{}');
      expect(prefs.getString('proxy_selection_weird'), 'keep');
      expect(prefs.getString('unrelated_key'), 'keep');
    });

    test('已有的 rev / inc 保留；未知字段与读不懂的条目原样保留', () async {
      final broken = {'id': '../evil', 'name': 'n', 'url': 'u', 'active': true};
      final prefs = await _seed(
        _v0(
          list: [
            _p(
              'a',
              more: {
                'rev': 7,
                'inc': 'mine',
                'futureField': {'k': 1},
              },
            ),
            broken,
            _p('a'), // 重复 id：不合法，也原样保留
            _p('b', more: {'rev': 0}), // 非法 rev 规整为 1
          ],
          active: 'b',
        ),
      );
      await _run(prefs);
      final list = _list(prefs);
      expect(list[0]['rev'], 7);
      expect(list[0]['inc'], 'mine');
      expect(list[0]['futureField'], {'k': 1});
      expect(list[1], broken, reason: '读不懂的条目一个字都不动');
      expect(list[2].containsKey('inc'), isFalse, reason: '重复 id 条目不补 inc');
      expect(list[3]['rev'], 1);
      expect(prefs.getString(_active), 'b');
    });

    test('备份键：写入迁移前的原值', () async {
      final raw = jsonEncode([_p('a', active: true)]);
      final prefs = await _seed({_profiles: raw, _active: 'a'});
      await _run(prefs);
      final backup = jsonDecode(
        prefs.getString(kMigrationBackupV0Key)!,
      ) as Map<String, dynamic>;
      expect(backup[_profiles], raw);
      expect(backup[_active], 'a');
    });

    test('备份保存原值与存在标记，包括类型不对的脏值', () async {
      final prefs = await _seed({_profiles: 42, _active: true});
      await _run(prefs);
      final backup = jsonDecode(
        prefs.getString(kMigrationBackupV0Key)!,
      ) as Map<String, dynamic>;
      expect(backup[_profiles], 42);
      expect(backup[_active], true);
      expect(backup['present'], {_profiles: true, _active: true});

      final lists = await _seed({_profiles: '[]', _active: 'x'});
      await prefs.reload();
      await _run(lists);
      // 字符串数组之类的脏值同样原样（可 JSON 编码）保存。
      final withList = await _seed({
        _profiles: ['a', 'b'],
      });
      await _run(withList);
      final b2 = jsonDecode(
        withList.getString(kMigrationBackupV0Key)!,
      ) as Map<String, dynamic>;
      expect(b2[_profiles], ['a', 'b']);
      expect(b2[_active], isNull);
      expect(b2['present'], {_profiles: true, _active: false});
    });

    test('备份遇到 NaN / ±Infinity 等脏值：带类型编码，迁移照常进行', () async {
      for (final bad in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        // 订阅列表有效、激活键误存成非有限浮点：迁移必须继续并选出激活项。
        final prefs = await _seed({
          _profiles: jsonEncode([_p('a'), _p('b', active: true)]),
          _active: bad,
        });
        final report = await _run(prefs);
        expect(report.outcome, MigrationOutcome.migrated, reason: '$bad');
        expect(prefs.getString(_active), 'b', reason: '$bad：脏值被正确的激活 id 取代');
        final backup = jsonDecode(
          prefs.getString(kMigrationBackupV0Key)!,
        ) as Map<String, dynamic>;
        final name = bad.isNaN
            ? 'NaN'
            : bad.isNegative
            ? '-Infinity'
            : 'Infinity';
        expect(backup[_active], {'t': 'double', 'v': name});
        expect(backup['present'], {_profiles: true, _active: true});
      }

      // 订阅键本身是非有限浮点：当作坏数据跳过订阅步骤，原值留在键上。
      final onList = await _seed({_profiles: double.nan});
      expect((await _run(onList)).outcome, MigrationOutcome.migrated);
      expect(onList.getDouble(_profiles)!.isNaN, isTrue);
      final b = jsonDecode(
        onList.getString(kMigrationBackupV0Key)!,
      ) as Map<String, dynamic>;
      expect(b[_profiles], {'t': 'double', 'v': 'NaN'});

      // 有限浮点原样保存。
      final finite = await _seed({_active: 1.5});
      await _run(finite);
      final fb = jsonDecode(
        finite.getString(kMigrationBackupV0Key)!,
      ) as Map<String, dynamic>;
      expect(fb[_active], 1.5);
    });

    test('备份键已存在：不覆盖', () async {
      final prefs = await _seed({
        ..._v0(list: [_p('a')]),
        kMigrationBackupV0Key: 'older-backup',
      });
      await _run(prefs);
      expect(prefs.getString(kMigrationBackupV0Key), 'older-backup');
    });

    test('外层 JSON 坏：跳过订阅相关步骤，原文、激活键、附属键都不动，schema 照样推进', () async {
      final prefs = await _seed({
        _profiles: '{not json[',
        _active: 'a',
        'proxy_selection_a': 'keep',
        'proxy_delays_zzz': 'keep',
      });
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.migrated);
      expect(prefs.getString(_profiles), '{not json[');
      expect(prefs.getString(_active), 'a');
      expect(prefs.getString('proxy_selection_a'), 'keep');
      expect(prefs.getString('proxy_delays_zzz'), 'keep');
      expect(prefs.getInt(kStorageSchemaKey), 1);
      // 备份仍然留着，坏原文可找回。
      expect(prefs.getString(kMigrationBackupV0Key), contains('not json'));
    });

    test('外层 JSON 是合法 JSON 但不是数组：同样当作坏的', () async {
      final prefs = await _seed({
        _profiles: '{"a":1}',
        'proxy_selection_x': '1',
      });
      await _run(prefs);
      expect(prefs.getString(_profiles), '{"a":1}');
      expect(prefs.getString('proxy_selection_x'), '1');
      expect(prefs.getInt(kStorageSchemaKey), 1);
    });

    test('订阅键存了错误类型：当作坏的，不抛', () async {
      final prefs = await _seed({_profiles: 42, _active: true});
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.migrated);
      expect(prefs.get(_profiles), 42);
      expect(prefs.getInt(kStorageSchemaKey), 1);
    });

    test('跑完再跑：第二次是 upToDate，没有任何写入', () async {
      final inner = await _seed(_v0(list: [_p('a', active: true), _p('b')]));
      await _run(inner);
      final after = _snapshot(inner);
      final prefs = CrashablePrefs(inner);
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.upToDate);
      expect(prefs.attempts, isEmpty);
      expect(_snapshot(inner), after);
    });

    test('schema 高于当前版本：什么都不动（含订阅数据）', () async {
      final inner = await _seed({
        ..._v0(
          list: [_p('a', active: true)],
          extra: {'proxy_selection_gone': 'x'},
        ),
        kStorageSchemaKey: kCurrentStorageSchema + 1,
      });
      final before = _snapshot(inner);
      final prefs = CrashablePrefs(inner);
      final report = await _run(prefs);
      expect(report.outcome, MigrationOutcome.newerSchema);
      expect(prefs.attempts, isEmpty);
      expect(_snapshot(inner), before);
    });
  });

  group('中断与写入失败', () {
    final fixture = _v0(
      list: [
        _p('a', active: false),
        _p('b', active: true, more: {'rev': 3}),
        _p('c', active: true),
        {'id': 'bad id', 'name': 'x', 'url': 'u'},
      ],
      active: 'ghost',
      extra: {
        'proxy_selection_a': '1',
        'proxy_selection_orphan1': '2',
        'proxy_delays_orphan2': '3',
        'proxy_delays_c': '4',
        'clashmiao_mixed_port': 2090,
      },
    );

    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('v1_mig_');
    });
    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('在每一个写入点之后中断，重跑都得到与一次跑完完全相同的结果；每个中间态业务读取都可用', () async {
      // 基准：一次跑完，同时数出总写入次数。
      final refInner = await _seed(fixture);
      final counting = CrashablePrefs(refInner);
      await _run(counting);
      final total = counting.applied;
      expect(total, greaterThan(4), reason: '备份/激活/重写/孤儿/schema 至少这么多次');
      final expected = _snapshot(refInner);

      for (var n = 0; n < total; n++) {
        final inner = await _seed(fixture);
        final crashed = CrashablePrefs(inner, allowedWrites: n);
        final first = await _run(crashed);
        expect(first.outcome, MigrationOutcome.failed, reason: 'n=$n 应失败');
        expect(
          inner.getInt(kStorageSchemaKey),
          isNull,
          reason: 'n=$n：写入失败后 schema 不能推进',
        );

        // 中间态：订阅与激活照常可读（兼容 v0 与 v1 两种格式）。
        final store = ProfileStore(prefs: inner, configDir: tmp);
        final ids = store.read().map((e) => e.id).toList();
        expect(ids, ['a', 'b', 'c'], reason: 'n=$n：中间态不丢订阅');
        expect(store.readActiveId(), isNotNull);
        expect(inner.getInt('clashmiao_mixed_port'), 2090);

        // 重跑（新进程：全新的 inc 生成器）。
        final second = await _run(inner);
        expect(second.outcome, MigrationOutcome.migrated, reason: 'n=$n 重跑');
        expect(_snapshot(inner), expected, reason: 'n=$n：重跑后与一次跑完一致');
      }
    });

    test('备份写入失败：什么都没被改动，schema 不变', () async {
      final inner = await _seed(fixture);
      final before = _snapshot(inner);
      final report = await _run(CrashablePrefs(inner, allowedWrites: 0));
      expect(report.outcome, MigrationOutcome.failed);
      expect(_snapshot(inner), before);
    });

    test('激活键写入失败：订阅 JSON 还没被重写（active 标记仍在，可重算）', () async {
      final inner = await _seed(fixture);
      // 第 1 次写是备份，第 2 次是激活键。
      final report = await _run(CrashablePrefs(inner, allowedWrites: 1));
      expect(report.outcome, MigrationOutcome.failed);
      expect(inner.getString(_active), 'ghost');
      expect(inner.getString(_profiles), (fixture[_profiles]));
      expect(inner.getInt(kStorageSchemaKey), isNull);
    });
  });

  group('迁移早期失败后继续使用：旧的激活信息不丢', () {
    // 评审用例：第一条是 a，旧版本标记激活的是 b，激活键悬空（ghost）或缺失；
    // 迁移在最前面的备份写入就失败，启动照常继续，业务写回，下次启动再迁移。
    for (final danglingKey in [true, false]) {
      final label = danglingKey ? '激活键悬空 ghost' : '激活键缺失';
      test('$label：读取退回旧 active 标记；业务写回保留标记；重跑后激活仍是 b', () async {
        final h = await ProfileHarness.create(
          legacy: true,
          initialPrefs: _v0(
            list: [_p('a', active: false), _p('b', active: true)],
            active: danglingKey ? 'ghost' : null,
          ),
        );
        addTearDown(h.dispose);

        // 迁移在备份写入处失败（一个写入都没生效）。
        final first = await StorageMigrator(
          migrations: [profilesV1Migration(incGenerator: _incs())],
        ).run(CrashablePrefs(h.prefs, allowedWrites: 0));
        expect(first.outcome, MigrationOutcome.failed);
        expect(h.prefs.getInt(kStorageSchemaKey), isNull);

        // 迁移没完成，业务读取也必须看到 b，而不是第一条 a（或 null）。
        expect(h.repo.getActive()?.id, 'b');
        expect(h.store.readActiveId(), 'b');
        expect(
          {for (final e in h.repo.getAll()) e.id: e.active},
          {'a': false, 'b': true},
        );

        // 业务写回（编辑非激活的 a、也编辑激活的 b）：整张列表被重写。
        await h.repo.editProfile('a', newName: 'a2');
        await h.repo.editProfile('b', newName: 'b2');
        expect(h.repo.getActive()?.id, 'b');
        final stored = h.storedJson;
        expect(
          {for (final e in stored) e['id']: e['active']},
          {'a': false, 'b': true},
          reason: '迁移未完成期间写回仍带着 active 标记',
        );
        expect(
          h.prefs.getString(_active),
          danglingKey ? 'ghost' : isNull,
          reason: '业务写回不碰激活键',
        );

        // 下次启动重跑迁移：激活恰好是 b，名字改动保留，active 标记被清理。
        final second = await StorageMigrator(
          migrations: [profilesV1Migration(incGenerator: _incs())],
        ).run(h.prefs);
        expect(second.outcome, MigrationOutcome.migrated);
        expect(h.prefs.getString(_active), 'b');
        expect(h.repo.getActive()?.id, 'b');
        final after = h.storedJson;
        expect(after.map((e) => e['name']), ['a2', 'b2']);
        expect(after.every((e) => !e.containsKey('active')), isTrue);
      });
    }

    test('迁移完成（schema ≥ 1）后恢复现行行为：悬空激活键回落第一条，写回不再带 active', () async {
      final h = await ProfileHarness.create(
        initialPrefs: _v0(
          list: [_p('a'), _p('b', active: true)],
          active: 'ghost',
        ),
      );
      addTearDown(h.dispose);
      expect(h.prefs.getInt(kStorageSchemaKey), kCurrentStorageSchema);
      expect(h.repo.getActive()?.id, 'a', reason: 'schema 1 起旧标记不再参与');
      await h.repo.editProfile('a', newName: 'x');
      expect(h.storedJson.every((e) => !e.containsKey('active')), isTrue);
    });

    test('激活键有效时，迁移未完成期间也以激活键为准', () async {
      final h = await ProfileHarness.create(
        legacy: true,
        initialPrefs: _v0(list: [_p('a'), _p('b', active: true)], active: 'a'),
      );
      addTearDown(h.dispose);
      expect(h.repo.getActive()?.id, 'a');
    });
  });
}
