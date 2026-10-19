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

  // 真实 SharedPreferences 先改内存缓存再写底层：底层写失败时缓存里留着没落盘的值。
  group('写入失败后缓存与磁盘对齐', () {
    for (final byThrowing in [false, true]) {
      final how = byThrowing ? '底层抛异常' : '底层返回 false';

      test('写 schema 失败（$how）：缓存重载回磁盘状态，报告一致，不再有后续写入，重跑会真正迁移', () async {
        final (store, prefs) = await FailingPrefsStore.install({'keep': 'v'});
        store
          ..failKeys = {kStorageSchemaKey}
          ..failByThrowing = byThrowing;
        final log = <int>[];

        final report = await StorageMigrator(
          migrations: [_step(1, log), _step(2, log)],
        ).run(prefs);

        expect(report.outcome, MigrationOutcome.failed);
        expect(report.toSchema, 0);
        expect(report.failedStep, 1);
        expect(log, [1], reason: '失败后不再跑后面的步骤');
        expect(store.attempts, [kStorageSchemaKey], reason: '失败后没有任何别的写入');
        // 缓存已与磁盘对齐：读不到没落盘的 schema。
        expect(prefs.getInt(kStorageSchemaKey), isNull);
        expect(
          (await store.persisted()).containsKey(kStorageSchemaKey),
          isFalse,
        );
        expect(prefs.getString('keep'), 'v');

        // 底层恢复后重跑：不是 upToDate，而是真的把步骤跑完并落盘。
        store.failKeys = {};
        final again = await StorageMigrator(
          migrations: [_step(1, log), _step(2, log)],
        ).run(prefs);
        expect(again.outcome, MigrationOutcome.migrated);
        expect(log, [1, 1, 2]);
        expect((await store.persisted())[kStorageSchemaKey], 2);
        expect(prefs.getInt(kStorageSchemaKey), 2);
      });
    }

    test('步骤自己的写入失败：缓存里没落盘的值被清掉，停止，不推进 schema', () async {
      final (store, prefs) = await FailingPrefsStore.install({});
      store.failKeys = {'marker'};
      final migration = Migration(
        toVersion: 1,
        name: 'writes',
        run: (p) async {
          if (!await p.setString('first', 'ok')) return false;
          if (!await p.setString('marker', 'lost')) return false;
          return p.setString('never', 'x'); // 不该走到这里
        },
      );

      final report = await StorageMigrator(migrations: [migration]).run(prefs);

      expect(report.outcome, MigrationOutcome.failed);
      expect(store.attempts, ['first', 'marker']);
      expect(prefs.getString('marker'), isNull, reason: '没落盘的值不能留在缓存里');
      expect(prefs.getString('first'), 'ok');
      expect(prefs.getInt(kStorageSchemaKey), isNull);
    });

    test('步骤抛出 PlatformException：同样重载、停止、不向外抛', () async {
      final (store, prefs) = await FailingPrefsStore.install({});
      store
        ..failKeys = {'marker'}
        ..failByThrowing = true;
      final migration = Migration(
        toVersion: 1,
        name: 'throws',
        run: (p) async {
          await p.setString('marker', 'lost');
          return true;
        },
      );
      final report = await StorageMigrator(migrations: [migration]).run(prefs);
      expect(report.outcome, MigrationOutcome.failed);
      expect(prefs.getString('marker'), isNull);
      expect(prefs.getInt(kStorageSchemaKey), isNull);
      expect(store.attempts, ['marker']);
    });
  });
}
