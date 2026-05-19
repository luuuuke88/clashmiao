import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/settings/model/backup_bundle.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class BackupService {
  static Future<void> export(WidgetRef ref) async {
    final repo = await ref.read(profileRepositoryProvider.future);

    final bundle = BackupBundle(
      version: BackupBundle.currentVersion,
      profiles: repo.getAll().map((p) => p.toJson()).toList(),
      activeProfileId: repo.getActive()?.id,
      settings: const {},
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final dir = await getTemporaryDirectory();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/clashmiao-backup-$date.json');
    await file.writeAsString(jsonEncode(bundle.toJson()));
    await Share.shareXFiles([XFile(file.path)], text: 'ClashMiao 备份');
  }

  static Future<String?> import(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return null;
    }

    final content = await File(result.files.single.path!).readAsString();
    final bundle = BackupBundle.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );

    final repo = await ref.read(profileRepositoryProvider.future);
    for (final p in bundle.profiles) {
      await repo.upsert(p);
    }
    if (bundle.activeProfileId != null) {
      await repo.setActive(bundle.activeProfileId!);
    }

    // Re-download config for URL-based profiles (local/content:// profiles are skipped)
    for (final p in bundle.profiles) {
      final url = p['url'] as String? ?? '';
      if (!url.startsWith('content://') &&
          url.isNotEmpty &&
          Uri.tryParse(url)?.hasScheme == true) {
        try {
          final id = p['id'] as String;
          await repo.update(id);
        } catch (_) {
          // best-effort; user can manually refresh if needed
        }
      }
    }

    return '已导入 ${bundle.profiles.length} 个订阅';
  }
}
