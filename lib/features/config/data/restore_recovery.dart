import 'dart:io';

import 'package:clashmiao/core/storage/pref_registry.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 恢复前快照所在目录：`<应用文档目录>/backups`。
Directory backupsDirIn(Directory documentsDir) =>
    Directory(p.join(documentsDir.path, 'backups'));

RecoveryOutcome? _lastOutcome;

/// 本进程启动时恢复标记检查的结果；启动前为 null。
///
/// [RecoveryOutcome.failed]（回滚没成功，标记保留）与
/// [RecoveryOutcome.unrecoverable]（快照丢了）需要让用户知道；界面层读这个值
/// 决定是否提示。
RecoveryOutcome? get lastRestoreRecoveryOutcome => _lastOutcome;

/// 在 [documentsDir] 下检查并处理中断的恢复。永不抛出。
Future<RecoveryOutcome> recoverInterruptedRestore(
  SharedPreferences prefs,
  Directory documentsDir,
) async {
  // 没有标记（绝大多数启动）就不必构造 Store 与引擎。
  final Object? marker;
  try {
    marker = prefs.get(kRestoreMarkerKey);
  } catch (_) {
    return RecoveryOutcome.none;
  }
  if (marker == null) return RecoveryOutcome.none;

  // 启动屏障阶段业务 provider 还没创建，这里用一个临时 Store：此时没有任何
  // 其它写入者，不存在锁竞争。
  final store = ProfileStore(prefs: prefs, configDir: documentsDir);
  try {
    final engine = BackupEngine(
      store: store,
      prefs: prefs,
      backupsDir: backupsDirIn(documentsDir),
      extraValidators: networkPrefValidators,
    );
    return await engine.recoverInterrupted();
  } finally {
    await store.dispose();
  }
}

/// 启动屏障的恢复标记检查（接给 `prepareStorage(checkRestoreMarker:)`）。
Future<void> checkRestoreMarkerAtStartup(SharedPreferences prefs) async {
  if (!prefs.containsKey(kRestoreMarkerKey)) {
    _lastOutcome = RecoveryOutcome.none;
    return;
  }
  final docs = await getApplicationDocumentsDirectory();
  final outcome = await recoverInterruptedRestore(prefs, Directory(docs.path));
  _lastOutcome = outcome;
  debugPrint('[storage] 恢复标记检查: ${outcome.name}');
}
