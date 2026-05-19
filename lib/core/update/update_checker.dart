import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _repoSlug = String.fromEnvironment('GITHUB_REPO_SLUG');
const _disabled = bool.fromEnvironment('CLASHMIAO_DISABLE_UPDATE_CHECK');
const _checkIntervalMs = 24 * 60 * 60 * 1000;
const _lastCheckKey = 'update_last_check_ms';
const _latestTagKey = 'update_latest_tag';

class UpdateChecker {
  static Future<String?> checkOnce(SharedPreferences prefs) async {
    if (_disabled || _repoSlug.isEmpty) return null;

    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < _checkIntervalMs) {
      return _compareToCurrentVersion(prefs.getString(_latestTagKey));
    }

    try {
      final resp = await Dio().get<Map<String, dynamic>>(
        'https://api.github.com/repos/$_repoSlug/releases/latest',
        options: Options(
          headers: {'Accept': 'application/vnd.github.v3+json'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final tag = resp.data?['tag_name'] as String?;
      if (tag != null) {
        await prefs.setString(_latestTagKey, tag);
        await prefs.setInt(_lastCheckKey, now);
        return _compareToCurrentVersion(tag);
      }
    } catch (_) {
      // network failure — silently ignore
    }
    return null;
  }

  static Future<String?> _compareToCurrentVersion(String? latestTag) async {
    if (latestTag == null) return null;
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final latest = latestTag.replaceFirst('v', '');
    return _isNewer(latest, current) ? latestTag : null;
  }

  static bool _isNewer(String latest, String current) {
    final l = latest.split('.');
    final c = current.split('.');
    for (var i = 0; i < 3; i++) {
      final li = int.tryParse(i < l.length ? l[i] : '0') ?? 0;
      final ci = int.tryParse(i < c.length ? c[i] : '0') ?? 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }
    return false;
  }
}

final updateAvailableProvider = FutureProvider<String?>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return UpdateChecker.checkOnce(prefs);
});
