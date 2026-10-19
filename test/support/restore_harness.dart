import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/domain/profile/model/profile_patch.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'temp_dirs.dart';
import 'write_fault_prefs.dart';

/// 一份最小的合法订阅配置（含 `outbounds` 数组）。
String sampleConfig(String tag) => jsonEncode({
  'outbounds': [
    {'type': 'direct', 'tag': tag},
  ],
});

/// 备份恢复测试的统一装置：真实文件系统 + 真实 [ProfileStore] / [BackupEngine]，
/// 偏好包一层可按键失败的 [WriteFaultPrefs]。
class RestoreHarness {
  RestoreHarness._({
    required this.tmp,
    required this.real,
    required this.prefs,
    required this.store,
    required this.engine,
  });

  final Directory tmp;
  final SharedPreferences real;
  final WriteFaultPrefs prefs;
  final ProfileStore store;
  final BackupEngine engine;

  Directory get backupsDir => Directory(p.join(tmp.path, 'backups'));

  static Future<RestoreHarness> create({
    Map<String, Object> initialPrefs = const {},
    int keepSnapshots = 3,
    bool legacy = false,
  }) async {
    // 默认是「启动迁移已经跑完」（schema 1）；旧数据场景传 `legacy: true`。
    SharedPreferences.setMockInitialValues({
      if (!legacy) kStorageSchemaKey: kCurrentStorageSchema,
      ...initialPrefs,
    });
    final real = await SharedPreferences.getInstance();
    final prefs = WriteFaultPrefs(real);
    final tmp = await Directory.systemTemp.createTemp('restore_harness_');
    final store = ProfileStore(prefs: prefs, configDir: tmp);
    var tick = DateTime.utc(2026, 3, 1);
    final engine = BackupEngine(
      store: store,
      prefs: prefs,
      backupsDir: Directory(p.join(tmp.path, 'backups')),
      extraValidators: networkPrefValidators,
      keepSnapshots: keepSnapshots,
      // 每次取值晚一秒：快照文件名按时间戳排序，不靠真实等待。
      now: () => tick = tick.add(const Duration(seconds: 1)),
    );
    return RestoreHarness._(
      tmp: tmp,
      real: real,
      prefs: prefs,
      store: store,
      engine: engine,
    );
  }

  Future<void> dispose() async {
    await store.dispose();
    await deleteTempDirBestEffort(tmp);
  }

  /// 种一条本机订阅（含配置文件）；[active] 为 true 时设为激活。
  Future<ProfileEntity> seed(
    String id, {
    String? url,
    String? config,
    bool active = false,
    String? name,
  }) async {
    final entity = ProfileEntity(
      id: id,
      name: name ?? 'name-$id',
      url: url ?? 'https://example.com/$id',
      inc: store.newInc(),
    );
    final staging = await store.createStagingFile(id);
    await staging.writeAsString(config ?? sampleConfig('local-$id'));
    final result = await store.commit<void>(
      (view) => Plan<void>(
        profiles: [...view.profiles, entity],
        activeId: active || view.activeId == null
            ? Patch<String>.set(id)
            : const Patch<String>.unset(),
        staged: [StagedConfig(id, staging)],
      ),
    );
    expectCommitted(result);
    return entity;
  }

  static void expectCommitted(CommitResult<Object?> result) {
    if (!result.isCommitted) {
      throw StateError('种数据失败: ${result.status} ${result.error}');
    }
  }

  /// 与「回到原状」比较用的全貌：订阅（不含本机 inc）、激活、`profiles/` 目录里
  /// **全部文件**（含 `.json` 配置、暂存 / undo 残留）的内容、全部偏好（订阅列表键
  /// 除外，它的 inc 会换新，列表已单独比较）。
  ///
  /// [via] 指定从哪个 Store 读列表 / 激活；传 [restartedStore] 的结果就是
  /// 「新进程只看磁盘与偏好」的视角。
  Future<Map<String, Object?>> state({ProfileStore? via}) async {
    final view = (via ?? store).view();
    final prefsSnapshot = <String, Object?>{
      for (final key in real.getKeys().toList()..sort())
        if (key != ProfileStore.profilesKey) key: real.get(key),
    };
    return {
      'profiles': [
        for (final profile in view.profiles)
          (Map<String, dynamic>.from(profile.toJson())..remove('inc')),
      ],
      'active': view.activeId,
      'files': allProfileFiles(),
      'prefs': prefsSnapshot,
    };
  }

  /// 模拟重启：全新的 Store，没有任何内存状态。
  ProfileStore restartedStore() => ProfileStore(prefs: real, configDir: tmp);

  /// `profiles/` 目录里每个文件的 文件名 → 内容（含所有残留）。
  Map<String, String> allProfileFiles() {
    final dir = Directory(p.join(tmp.path, 'profiles'));
    if (!dir.existsSync()) return const {};
    return {
      for (final f in dir.listSync().whereType<File>())
        p.basename(f.path): f.readAsStringSync(),
    };
  }

  List<String> strayFiles() {
    final dir = Directory(p.join(tmp.path, 'profiles'));
    if (!dir.existsSync()) return const [];
    return [
      for (final f in dir.listSync())
        if (f is File && !p.basename(f.path).endsWith('.json'))
          p.basename(f.path),
    ]..sort();
  }

  List<File> snapshots() {
    if (!backupsDir.existsSync()) return const [];
    return [
      for (final f in backupsDir.listSync())
        if (f is File && p.basename(f.path).startsWith('pre-restore-')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }
}
