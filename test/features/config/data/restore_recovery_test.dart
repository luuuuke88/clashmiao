import 'dart:async';
import 'dart:io';

import 'package:clashmiao/app/bootstrap/storage_bootstrap.dart';
import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/data/restore_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../support/restore_harness.dart';

String _backupJson() =>
    '''
{"version":2,"schema":1,"createdAt":1,
 "profiles":[{"id":"c","name":"from-backup","url":"https://example.com/c",
   "lastUpdate":null,"updateInterval":1,"subInfo":null,"customUserAgent":null,"rev":1}],
 "activeProfileId":"c",
 "profileConfigs":{"c":${_q(sampleConfig('backup-c'))}},
 "preferences":{"clashmiao_mixed_port":3000,"theme_mode":"light"}}
''';

String _q(String s) => '"${s.replaceAll('"', r'\"')}"';

/// 把一次恢复在「偏好写到一半」时卡住（进程被杀），返回被卡住的引擎之外的现场。
Future<void> _killMidRestore(RestoreHarness h) async {
  final killed = Completer<void>();
  final never = Completer<void>();
  h.prefs.beforeWrite = (op, key) async {
    if (op == 'set' && key == 'theme_mode') {
      if (!killed.isCompleted) killed.complete();
      await never.future;
    }
  };
  unawaited(
    h.engine
        .restore(h.engine.prepare(_backupJson()))
        .then<void>((_) {}, onError: (_) {}),
  );
  await killed.future;
  h.prefs.beforeWrite = null;
}

void main() {
  late RestoreHarness h;
  tearDown(() async => h.dispose());

  test('启动：发现恢复标记 → 用快照自动回到恢复前，再继续迁移', () async {
    // 旧版本数据（schema 缺失）+ 一次被杀的恢复。
    h = await RestoreHarness.create(
      legacy: true,
      initialPrefs: {'clashmiao_mixed_port': 2080, 'theme_mode': 'dark'},
    );
    await h.seed('a', active: true, config: sampleConfig('local-a'));
    await h.seed('b', config: sampleConfig('local-b'));
    final before = await h.state();
    await _killMidRestore(h);
    expect(h.real.containsKey(kRestoreMarkerKey), isTrue);
    expect(h.store.read().map((e) => e.id), ['c'], reason: '被杀时已经是半成品');

    final order = <String>[];
    await prepareStorage(
      h.real,
      checkRestoreMarker: (prefs) async {
        order.add('recover(schema=${prefs.getInt(kStorageSchemaKey)})');
        final outcome = await recoverInterruptedRestore(prefs, h.tmp);
        order.add(outcome.name);
      },
    );

    expect(order, ['recover(schema=null)', 'recovered'], reason: '恢复先于迁移');
    // 回到被杀之前的订阅 / 配置 / 偏好；迁移随后照常完成。
    expect(h.store.read().map((e) => e.id), ['a', 'b']);
    expect(h.store.readActiveId(), 'a');
    expect(
      File(h.store.configFilePath('a')).readAsStringSync(),
      sampleConfig('local-a'),
    );
    expect(File(h.store.configFilePath('c')).existsSync(), isFalse);
    expect(h.real.getInt('clashmiao_mixed_port'), 2080);
    expect(h.real.getString('theme_mode'), 'dark');
    expect(h.real.containsKey(kRestoreMarkerKey), isFalse);
    expect(h.real.getInt(kStorageSchemaKey), kCurrentStorageSchema);
    expect(h.real.getString(ProfileStore.activeProfileKey), 'a');
    final after = await h.state();
    expect(after['profiles'], before['profiles']);
    expect(after['files'], before['files']);
  });

  test('没有标记：不构造 Store、不碰 backups 目录', () async {
    h = await RestoreHarness.create();
    await h.seed('a');
    final before = await h.state();
    expect(
      await recoverInterruptedRestore(h.real, h.tmp),
      RecoveryOutcome.none,
    );
    expect(await h.state(), before);
    expect(h.backupsDir.existsSync(), isFalse);
  });

  test('标记指向的快照丢了：报告 unrecoverable，标记清除，本机数据不动', () async {
    h = await RestoreHarness.create();
    await h.seed('a');
    await h.real.setString(
      kRestoreMarkerKey,
      p.join(h.backupsDir.path, 'pre-restore-gone.json'),
    );
    expect(
      await recoverInterruptedRestore(h.real, h.tmp),
      RecoveryOutcome.unrecoverable,
    );
    expect(h.real.containsKey(kRestoreMarkerKey), isFalse);
    expect(h.store.read().map((e) => e.id), ['a']);
  });
}
