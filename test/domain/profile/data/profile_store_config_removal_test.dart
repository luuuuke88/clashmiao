import 'dart:io';

import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/temp_dirs.dart';
import '../../../support/write_fault_prefs.dart';

/// `Plan.removedConfigIds`（订阅留在列表里、只删配置文件）的收尾与残留语义。
///
/// 关键点：它的残留必须和普通替换的 `.undo` 区分开——订阅还在列表里，
/// 残留的 `.undo` 会被启动清理当成「正式文件缺失」而还原，复活本应不存在的文件。
void main() {
  late Directory tmp;
  late WriteFaultPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = WriteFaultPrefs(await SharedPreferences.getInstance());
    tmp = await Directory.systemTemp.createTemp('store_cfg_removal_');
  });
  tearDown(() => deleteTempDirBestEffort(tmp));

  ProfileStore makeStore({
    Future<void> Function(File)? deleteFile,
    Future<File> Function(File, String)? renameFile,
  }) => ProfileStore(
    prefs: prefs,
    configDir: tmp,
    deleteFile: deleteFile,
    renameFile: renameFile,
  );

  /// 种一条订阅 b，带配置文件。
  Future<void> seedB(ProfileStore store) async {
    final staging = await store.createStagingFile('b');
    await staging.writeAsString('{"outbounds":[]}');
    final r = await store.commit<void>(
      (view) => Plan<void>(
        profiles: [
          const ProfileEntity(id: 'b', name: 'b', url: 'https://x/b', inc: 'i'),
        ],
        staged: [StagedConfig('b', staging)],
      ),
    );
    expect(r.isCommitted, isTrue);
  }

  File formal(ProfileStore s) => File(s.configFilePath('b'));

  List<String> residue() => [
    for (final f in Directory(p.join(tmp.path, 'profiles')).listSync())
      if (f is File && !p.basename(f.path).endsWith('.json'))
        p.basename(f.path),
  ];

  Future<CommitResult<void>> removeConfigOnly(ProfileStore s) =>
      s.commit<void>((view) => const Plan<void>(removedConfigIds: ['b']));

  test('正常：配置删掉、订阅仍在列表、没有残留', () async {
    final store = makeStore();
    await seedB(store);
    final r = await removeConfigOnly(store);
    expect(r.isCommitted, isTrue);
    expect(r.incompleteCleanup, isEmpty);
    expect(formal(store).existsSync(), isFalse);
    expect(store.exists('b'), isTrue);
    expect(residue(), isEmpty);
  });

  test('收尾删除失败：残留是 .del（不是 .undo），提交结果标出未完成；重启清理删完它，不复活', () async {
    final store = makeStore(
      deleteFile: (_) async => throw const FileSystemException('busy'),
    );
    await seedB(store);
    final r = await removeConfigOnly(store);

    expect(r.isCommitted, isTrue);
    expect(r.incompleteCleanup, hasLength(1));
    expect(r.incompleteCleanup.single, endsWith('.del'));
    expect(formal(store).existsSync(), isFalse);
    expect(residue().single, endsWith('.del'));
    expect(await store.pendingConfigDeletions(), hasLength(1));

    // 重启：全新 Store（没有故障）。订阅仍在列表里，但残留是 .del——只能删完。
    final restarted = makeStore();
    expect(restarted.exists('b'), isTrue);
    await restarted.cleanupResidue();
    expect(formal(restarted).existsSync(), isFalse, reason: '不能被还原');
    expect(residue(), isEmpty);
    expect(await restarted.pendingConfigDeletions(), isEmpty);
  });

  test('重启清理时删除仍然失败：残留保留且被报告为待处理，之后恢复正常再删完', () async {
    final failing = makeStore(
      deleteFile: (_) async => throw const FileSystemException('busy'),
    );
    await seedB(failing);
    await removeConfigOnly(failing);

    final stillFailing = makeStore(
      deleteFile: (_) async => throw const FileSystemException('busy'),
    );
    await stillFailing.cleanupResidue();
    expect(await stillFailing.pendingConfigDeletions(), hasLength(1));
    expect(formal(stillFailing).existsSync(), isFalse);

    final healthy = makeStore();
    await healthy.cleanupResidue();
    expect(await healthy.pendingConfigDeletions(), isEmpty);
    expect(formal(healthy).existsSync(), isFalse);
  });

  test('改名和删除都失败：留下的是 .undo，同样被标为未完成（调用者必须保留重试线索）', () async {
    final store = makeStore(
      deleteFile: (_) async => throw const FileSystemException('busy'),
      renameFile: (_, _) async => throw const FileSystemException('busy'),
    );
    await seedB(store);
    final r = await removeConfigOnly(store);
    expect(r.isCommitted, isTrue);
    expect(r.incompleteCleanup.single, endsWith('.undo'));
  });

  test('提交失败（写列表返回 false）：配置文件原样还原，没有残留', () async {
    final store = makeStore();
    await seedB(store);
    prefs.failWhen = (op, key) =>
        op == 'set' && key == ProfileStore.profilesKey;
    final r = await store.commit<void>(
      (view) => Plan<void>(
        profiles: [view.profiles.single.copyWith(name: 'renamed')],
        removedConfigIds: const ['b'],
      ),
    );
    prefs.failWhen = null;
    expect(r.isFailed, isTrue);
    expect(formal(store).readAsStringSync(), '{"outbounds":[]}');
    expect(residue(), isEmpty);
  });

  test('普通 .undo 语义不变：订阅在列表、正式文件缺失 → 还原；正式文件在 → 删 .undo', () async {
    final store = makeStore();
    await seedB(store);
    final dir = p.join(tmp.path, 'profiles');
    // 模拟刷新时死在「文件已换、列表未写」之后：正式文件被改名成 .undo。
    formal(store).renameSync(p.join(dir, 'b.json.deadbeef.undo'));
    await makeStore().cleanupResidue();
    expect(formal(store).readAsStringSync(), '{"outbounds":[]}');
    expect(residue(), isEmpty);

    File(p.join(dir, 'b.json.cafe.undo')).writeAsStringSync('old');
    await makeStore().cleanupResidue();
    expect(formal(store).readAsStringSync(), '{"outbounds":[]}');
    expect(residue(), isEmpty);
  });
}
