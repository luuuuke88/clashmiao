import 'dart:async';
import 'dart:io';

import 'package:clashmiao/app/bootstrap/storage_bootstrap.dart';
import 'package:clashmiao/core/storage/storage_migrator.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs(Map<String, Object> v) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

void main() {
  const v0 = {
    ProfileStore.profilesKey:
        '[{"id":"a","name":"n","url":"http://x/a","active":true}]',
  };

  test('启动屏障：先做恢复标记检查，再迁移', () async {
    final prefs = await _prefs(v0);
    int? schemaSeenByCheck = -1;
    await prepareStorage(
      prefs,
      checkRestoreMarker: (p) async {
        schemaSeenByCheck = p.getInt(kStorageSchemaKey);
      },
    );
    expect(schemaSeenByCheck, isNull, reason: '检查发生时还没迁移');
    expect(prefs.getInt(kStorageSchemaKey), kCurrentStorageSchema);
    expect(prefs.getString(ProfileStore.activeProfileKey), 'a');
  });

  test('恢复标记检查抛错：不挡住启动，迁移照常进行', () async {
    final prefs = await _prefs(v0);
    await prepareStorage(
      prefs,
      checkRestoreMarker: (_) async => throw StateError('boom'),
    );
    expect(prefs.getInt(kStorageSchemaKey), kCurrentStorageSchema);
  });

  test('没有接入恢复检查时（C1-3 之前）也能正常迁移', () async {
    final prefs = await _prefs(v0);
    final report = await prepareStorage(prefs);
    expect(report.toSchema, kCurrentStorageSchema);
  });

  test('高 schema：不动数据，不抛', () async {
    final prefs = await _prefs({...v0, kStorageSchemaKey: 99});
    await prepareStorage(prefs);
    expect(prefs.getInt(kStorageSchemaKey), 99);
    expect(prefs.containsKey(ProfileStore.activeProfileKey), isFalse);
  });

  // Completer 卡住异步步骤，证明「await 屏障」真的在等，而不是碰巧顺序对。
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('恢复标记检查没做完：迁移一步都不会开始', () async {
    final prefs = await _prefs(v0);
    final restoreGate = Completer<void>();
    var migrationStarted = false;
    final migrator = StorageMigrator(
      migrations: [
        Migration(
          toVersion: 1,
          name: 'probe',
          run: (_) async {
            migrationStarted = true;
            return true;
          },
        ),
      ],
    );

    var done = false;
    final boot =
        prepareStorage(
          prefs,
          checkRestoreMarker: (_) => restoreGate.future,
          migrator: migrator,
        ).then((r) {
          done = true;
          return r;
        });
    await settle();
    await settle();
    expect(migrationStarted, isFalse, reason: '恢复检查未完成，迁移不能开始');
    expect(done, isFalse);

    restoreGate.complete();
    await boot;
    expect(migrationStarted, isTrue);
    expect(done, isTrue);
  });

  test('迁移没做完：屏障不放行，其后的业务读取与原生推送必须等待', () async {
    final prefs = await _prefs(v0);
    final migrationGate = Completer<bool>();
    final migrator = StorageMigrator(
      migrations: [
        Migration(toVersion: 1, name: 'slow', run: (_) => migrationGate.future),
      ],
    );

    // 与 main() 同样的形状：先 await 屏障，再读业务数据、推原生配置。
    final order = <String>[];
    final boot = () async {
      await prepareStorage(prefs, migrator: migrator);
      order.add('business-read');
      order.add('native-push');
    }();

    await settle();
    await settle();
    expect(order, isEmpty, reason: '迁移卡住时业务读取与原生推送都不能发生');

    migrationGate.complete(true);
    await boot;
    expect(order, ['business-read', 'native-push']);
  });

  test('main() 里屏障先于任何业务 provider 读取、内核初始化与原生配置推送', () {
    final source = File('lib/main.dart').readAsStringSync();
    final main = source.substring(source.indexOf('void main()'));
    final barrier = main.indexOf('await prepareStorage(');
    expect(barrier, isNonNegative, reason: 'main() 必须 await 屏障');
    for (final later in [
      'boxServiceProvider',
      'networkSettingsProvider',
      'changeConfigOptions',
      'themePreferencesProvider',
      'profileRepositoryProvider',
      '_devAutoBoot(',
      'runApp(',
    ]) {
      final at = main.indexOf(later);
      if (at < 0) continue;
      expect(barrier, lessThan(at), reason: '$later 不能出现在屏障之前');
    }
    expect(
      main.indexOf('sharedPreferencesProvider.future'),
      lessThan(barrier),
      reason: '屏障需要先加载 prefs',
    );
  });

  test('迁移失败：报告被记下；同一进程内再次调用仍是失败，不会变成 upToDate', () async {
    final prefs = await _prefs(v0);
    var runs = 0;
    final migrator = StorageMigrator(
      migrations: [
        Migration(
          toVersion: 1,
          name: 'fails',
          run: (p) async {
            runs++;
            await p.setInt(kStorageSchemaKey, 1); // 模拟平台缓存已改但落盘失败
            return false;
          },
        ),
      ],
    );
    final first = await prepareStorage(prefs, migrator: migrator);
    expect(first.outcome, MigrationOutcome.failed);
    expect(lastStorageMigrationReport?.outcome, MigrationOutcome.failed);
    // 缓存里的 schema 已是 1，但不能据此认为迁移成功。
    expect(prefs.getInt(kStorageSchemaKey), 1);
    final second = await prepareStorage(prefs, migrator: migrator);
    expect(second.outcome, MigrationOutcome.failed);
    expect(runs, 1);
  });
}
