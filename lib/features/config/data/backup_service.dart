import 'dart:io';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/config/application/restore_refresher.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/data/backup_engine.dart';
import 'package:clashmiao/features/config/data/restore_recovery.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 已选好文件并完整校验过（尚未写任何东西）的一次导入，等待用户确认。
class PreparedImport {
  const PreparedImport({required this.plan, required this.willRemove});

  final RestorePlan plan;

  /// 本机有、备份里没有、确认后会被移除的订阅。
  final List<ProfileEntity> willRemove;
}

/// 备份导出 / 导入的界面入口：负责文件选择与分享，业务都在 [BackupEngine] 与
/// [RestoreRefresher]。
///
/// 接收 [ProviderContainer] 而不是 `WidgetRef`：导入要在后台继续补拉订阅，
/// 页面销毁后 `WidgetRef` 就不能用了。页面用 `ProviderScope.containerOf(context)` 取。
class BackupService {
  const BackupService._();

  static Future<BackupEngine> engine(ProviderContainer container) =>
      engineWith(container.read);

  /// 用任意「读 provider」的入口（`ref.read` / `container.read`）构造引擎。
  /// 恢复互斥挂在 [ProfileStore] 上，所以每次新建引擎也共享同一把互斥。
  static Future<BackupEngine> engineWith(
    T Function<T>(ProviderListenable<T> provider) read,
  ) async {
    final store = await read(profileStoreProvider.future);
    final prefs = await read(sharedPreferencesProvider.future);
    final docs = await getApplicationDocumentsDirectory();
    return BackupEngine(
      store: store,
      prefs: prefs,
      backupsDir: backupsDirIn(Directory(docs.path)),
      extraValidators: networkPrefValidators,
    );
  }

  /// 导出一致快照并交给系统分享。备份里没有机密与运行时键。
  static Future<void> export(ProviderContainer container) async {
    final backup = await (await engine(container)).exportBundle();
    final dir = await getTemporaryDirectory();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/clashmiao-backup-$date.json');
    await file.writeAsString(BackupCodec.encode(backup));
    await Share.shareXFiles([XFile(file.path)], text: 'ClashMiao 备份');
  }

  /// 让用户选一个备份文件并完整校验。用户取消返回 null；文件不可用抛
  /// [BackupFormatException]。不写任何东西。
  static Future<PreparedImport?> pickAndPrepare(
    ProviderContainer container,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }
    final raw = await File(result.files.single.path!).readAsString();
    return prepare(container, raw);
  }

  static Future<PreparedImport> prepare(
    ProviderContainer container,
    String raw,
  ) async {
    final engine = await BackupService.engine(container);
    final plan = engine.prepare(raw);
    return PreparedImport(plan: plan, willRemove: engine.removedBy(plan));
  }

  /// 用户确认后应用。失败抛 [RestoreFailure]；成功后界面已刷新，缺配置的远程
  /// 订阅在后台补拉（[RestoreOutcome.backfill]）。
  static Future<RestoreOutcome> apply(
    ProviderContainer container,
    PreparedImport prepared,
  ) async {
    final engine = await BackupService.engine(container);
    final refresher = RestoreRefresher(
      container: container,
      extraInvalidations: container.read(restoreExtraInvalidationsProvider),
    );
    return refresher.restore(engine, prepared.plan);
  }
}
