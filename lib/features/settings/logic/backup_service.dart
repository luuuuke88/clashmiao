import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/settings/model/backup_bundle.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BackupService {
  static Future<void> export(WidgetRef ref) async {
    final repo = await ref.read(profileRepositoryProvider.future);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final profiles = repo.getAll();
    final profileConfigs = <String, String>{};
    for (final profile in profiles) {
      final file = File(repo.configFilePath(profile.id));
      if (await file.exists()) {
        profileConfigs[profile.id] = await file.readAsString();
      }
    }

    final bundle = BackupBundle(
      version: BackupBundle.currentVersion,
      profiles: profiles.map((p) => p.toJson()).toList(),
      activeProfileId: repo.getActive()?.id,
      settings: {
        'profileConfigs': profileConfigs,
        'preferences': _exportPreferences(prefs),
      },
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
    final Map<String, dynamic> jsonMap;
    try {
      jsonMap = jsonDecode(content) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('备份文件格式无效，请确认选择的是 ClashMiao 导出的 JSON 文件');
    }
    final bundle = BackupBundle.fromJson(jsonMap);

    final repo = await ref.read(profileRepositoryProvider.future);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final exportedPrefs = bundle.settings['preferences'];
    if (exportedPrefs is Map) {
      await _importPreferences(prefs, Map<String, dynamic>.from(exportedPrefs));
    }

    final profileConfigs = bundle.settings['profileConfigs'] is Map
        ? Map<String, dynamic>.from(bundle.settings['profileConfigs'] as Map)
        : const <String, dynamic>{};

    for (final p in bundle.profiles) {
      await repo.upsert(p);
      final id = p['id'] as String?;
      final content = id == null ? null : profileConfigs[id] as String?;
      if (id != null && content != null) {
        final file = File(repo.configFilePath(id));
        await file.parent.create(recursive: true);
        await file.writeAsString(content);
      }
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

  static Map<String, dynamic> _exportPreferences(SharedPreferences prefs) {
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (key == 'clashmiao_profiles' || key == 'clashmiao_active_profile') {
        continue;
      }
      final shouldExport =
          key.startsWith('clashmiao_') ||
          key.startsWith('per_app_proxy_') ||
          {
            'service-mode',
            'debug_mode',
            'disable_memory_limit',
            'dynamic_notification',
            'system_proxy_enabled',
          }.contains(key);
      if (!shouldExport) continue;
      out[key] = prefs.get(key);
    }
    return out;
  }

  static Future<void> _importPreferences(
    SharedPreferences prefs,
    Map<String, dynamic> values,
  ) async {
    for (final entry in values.entries) {
      final value = entry.value;
      switch (value) {
        case bool v:
          await prefs.setBool(entry.key, v);
        case int v:
          await prefs.setInt(entry.key, v);
        case double v:
          await prefs.setDouble(entry.key, v);
        case String v:
          await prefs.setString(entry.key, v);
        case List v:
          if (v.every((e) => e is String)) {
            await prefs.setStringList(entry.key, v.cast<String>());
          }
      }
    }
  }
}
