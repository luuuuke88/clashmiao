import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/crashable_prefs.dart';
import '../../support/failing_prefs_store.dart';

Future<SharedPreferences> _prefs([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(Map.of(initial));
  return SharedPreferences.getInstance();
}

Migration _step(int to, List<int> log, {bool ok = true, bool throws = false}) {
  return Migration(
    toVersion: to,
    name: 'v$to',
    run: (prefs) async {
      log.add(to);
      if (throws) throw StateError('boom');
      return ok;
    },
  );
}

void main() {
  group('StorageMigrator', () {
    test('缺失 schema 视为 0：依次跑完所有步骤并推进到目标版本', () async {
      final prefs = await _prefs();
      final log = <int>[];
      final report = await StorageMigrator(
        migrations: [_step(1, log), _step(2, log)],
      ).run(prefs);
      expect(log, [1, 2]);
      expect(report.outcome, MigrationOutcome.migrated);
      expect(report.fromSchema, 0);
      expect(report.toSchema, 2);
      expect(prefs.getInt(kStorageSchemaKey), 2);
    });

    test('已经在目标版本：什么都不跑、不写任何键', () async {
      final prefs = CrashablePrefs(await _prefs({kStorageSchemaKey: 1}));
      final log = <int>[];
      final report = await StorageMigrator(
        migrations: [_step(1, log)],
      ).run(prefs);
      expect(log, isEmpty);
      expect(report.outcome, MigrationOutcome.upToDate);
      expect(prefs.attempts, isEmpty);
    });

    test('只跑高于当前版本的步骤', () async {
      final prefs = await _prefs({kStorageSchemaKey: 1});
      final log = <int>[];
      await StorageMigrator(
        migrations: [_step(1, log), _step(2, log)],
      ).run(prefs);
      expect(log, [2]);
      expect(prefs.getInt(kStorageSchemaKey), 2);
    });

    test('schema 高于目标（用户降级）：不迁移、不写任何东西', () async {
      final inner = await _prefs({kStorageSchemaKey: 7, 'k': 'v'});
      final prefs = CrashablePrefs(inner);
      final log = <int>[];
      final report = await StorageMigrator(
        migrations: [_step(1, log)],
      ).run(prefs);
      expect(log, isEmpty);
      expect(report.outcome, MigrationOutcome.newerSchema);
      expect(prefs.attempts, isEmpty);
      expect(inner.getInt(kStorageSchemaKey), 7);
    });

    test('步骤返回 false：停止，不推进 schema，后面的步骤不跑', () async {
      final prefs = await _prefs({kStorageSchemaKey: 0});
      final log = <int>[];
      final report = await StorageMigrator(
        migrations: [_step(1, log), _step(2, log, ok: false), _step(3, log)],
      ).run(prefs);
      expect(log, [1, 2]);
      expect(report.outcome, MigrationOutcome.failed);
      expect(report.failedStep, 2);
      // 第 1 步已完整成功，版本停在 1；第 2 步失败不推进。
      expect(prefs.getInt(kStorageSchemaKey), 1);
      expect(report.toSchema, 1);
    });

    test('步骤抛异常：当作失败，不向外抛', () async {
      final prefs = await _prefs();
      final report = await StorageMigrator(
        migrations: [_step(1, [], throws: true)],
      ).run(prefs);
      expect(report.outcome, MigrationOutcome.failed);
      expect(prefs.getInt(kStorageSchemaKey), isNull);
    });

    test('写 schema 本身失败：算失败，版本不推进', () async {
      final inner = await _prefs();
      final prefs = CrashablePrefs(inner, allowedWrites: 0);
      final report = await StorageMigrator(
        migrations: [_step(1, [])],
      ).run(prefs);
      expect(report.outcome, MigrationOutcome.failed);
      expect(inner.getInt(kStorageSchemaKey), isNull);
    });

    test('schema 键存了错误类型：按 0 处理并改写成整数', () async {
      final prefs = await _prefs({kStorageSchemaKey: 'oops'});
      final log = <int>[];
      await StorageMigrator(migrations: [_step(1, log)]).run(prefs);
      expect(log, [1]);
      expect(prefs.getInt(kStorageSchemaKey), 1);
    });

    test('步骤版本必须从 1 起连续递增', () {
      expect(
        () => StorageMigrator(migrations: [_step(2, [])]),
        throwsArgumentError,
      );
      expect(
        () => StorageMigrator(migrations: [_step(1, []), _step(1, [])]),
        throwsArgumentError,
      );
    });
  });

  // 平台后端先改自己的内存缓存、再落盘：写盘失败后缓存里留着没落盘的值，
  // `prefs.reload()` 也只会读回这份缓存——所以失败必须在进程内粘滞。
  group('写入失败在本进程内粘滞（平台缓存先改、落盘失败）', () {
    for (final byThrowing in [false, true]) {
      final how = byThrowing ? '底层抛异常' : '底层返回 false';

      test('写 schema 失败（$how）：报告失败、其后零写入、进程内重跑仍是失败；新进程重新迁移到正确状态', () async {
        final (store, prefs) = await FailingPrefsStore.install({'keep': 'v'});
        store
          ..failKeys = {kStorageSchemaKey}
          ..failByThrowing = byThrowing;
        final log = <int>[];
        final migrator = StorageMigrator(
          migrations: [_step(1, log), _step(2, log)],
        );

        final report = await migrator.run(prefs);

        // 独立断言各个可观察量。
        expect(report.outcome, MigrationOutcome.failed);
        expect(report.failed, isTrue);
        expect(report.toSchema, 0);
        expect(report.failedStep, 1);
        expect(log, [1], reason: '失败后不再跑后面的步骤');
        expect(store.attempts, [kStorageSchemaKey], reason: '失败后没有任何别的写入');
        expect(store.disk.containsKey(kStorageSchemaKey), isFalse);
        // 场景本身：平台缓存「说」schema 已经是 1（这正是不能靠重读判断的原因）。
        expect(prefs.getInt(kStorageSchemaKey), 1);

        // 同进程再来一次：同一份失败结果，绝不是 upToDate，且不读不写不跑。
        final again = await migrator.run(prefs);
        expect(again.outcome, MigrationOutcome.failed);
        expect(again.outcome, isNot(MigrationOutcome.upToDate));
        expect(again.failedStep, 1);
        expect(again.toSchema, 0);
        expect(log, [1], reason: '进程内不重跑步骤');
        expect(store.attempts, [kStorageSchemaKey], reason: '进程内重跑也没有新写入');
        expect(migrator.failure, isNotNull);

        // 新进程：用磁盘内容重新装一份存储与迁移器，幂等重跑后状态正确。
        final (store2, prefs2) = await FailingPrefsStore.install(store.disk);
        expect(prefs2.getInt(kStorageSchemaKey), isNull, reason: '新进程读到的是磁盘');
        final log2 = <int>[];
        final fresh = await StorageMigrator(
          migrations: [_step(1, log2), _step(2, log2)],
        ).run(prefs2);
        expect(fresh.outcome, MigrationOutcome.migrated);
        expect(log2, [1, 2]);
        expect(store2.disk[kStorageSchemaKey], 2);
        expect(store2.disk['keep'], 'v');
      });
    }

    test('步骤自己的写入失败：停止、其后零写入、进程内重跑仍失败；新进程幂等重跑到正确状态', () async {
      final (store, prefs) = await FailingPrefsStore.install({});
      store.failKeys = {'marker'};
      var runs = 0;
      Migration build() => Migration(
        toVersion: 1,
        name: 'writes',
        run: (p) async {
          runs++;
          if (!await p.setString('first', 'ok')) return false;
          if (!await p.setString('marker', 'done')) return false;
          return p.setString('never', 'x'); // 失败后不该走到这里
        },
      );
      final migrator = StorageMigrator(migrations: [build()]);

      final report = await migrator.run(prefs);
      expect(report.outcome, MigrationOutcome.failed);
      expect(store.attempts, ['first', 'marker']);
      expect(store.disk, {'first': 'ok'}, reason: '只有成功落盘的写入在磁盘上');
      expect(prefs.getInt(kStorageSchemaKey), isNull);

      final again = await migrator.run(prefs);
      expect(again.outcome, MigrationOutcome.failed);
      expect(runs, 1);
      expect(store.attempts, ['first', 'marker']);

      final (store2, prefs2) = await FailingPrefsStore.install(store.disk);
      final fresh = await StorageMigrator(migrations: [build()]).run(prefs2);
      expect(fresh.outcome, MigrationOutcome.migrated);
      expect(store2.disk, {
        'first': 'ok',
        'marker': 'done',
        'never': 'x',
        kStorageSchemaKey: 1,
      });
    });

    test('步骤抛出 PlatformException：同样失败、粘滞、不向外抛', () async {
      final (store, prefs) = await FailingPrefsStore.install({});
      store
        ..failKeys = {'marker'}
        ..failByThrowing = true;
      final migrator = StorageMigrator(
        migrations: [
          Migration(
            toVersion: 1,
            name: 'throws',
            run: (p) async {
              await p.setString('marker', 'lost');
              return true;
            },
          ),
        ],
      );
      expect((await migrator.run(prefs)).outcome, MigrationOutcome.failed);
      expect((await migrator.run(prefs)).outcome, MigrationOutcome.failed);
      expect(store.attempts, ['marker']);
      expect(store.disk, isEmpty);
    });

    test('失败之前已成功的运行不受影响：成功后的再次运行是 upToDate', () async {
      final (store, prefs) = await FailingPrefsStore.install({});
      final migrator = StorageMigrator(migrations: [_step(1, [])]);
      expect((await migrator.run(prefs)).outcome, MigrationOutcome.migrated);
      expect((await migrator.run(prefs)).outcome, MigrationOutcome.upToDate);
      expect(store.disk[kStorageSchemaKey], 1);
    });

    test('并发调用共享同一次运行：步骤只跑一次', () async {
      final prefs = await _prefs();
      final log = <int>[];
      final migrator = StorageMigrator(migrations: [_step(1, log)]);
      final results = await Future.wait([
        migrator.run(prefs),
        migrator.run(prefs),
      ]);
      expect(log, [1]);
      expect(
        results.map((r) => r.outcome),
        everyElement(MigrationOutcome.migrated),
      );
    });
  });
}
