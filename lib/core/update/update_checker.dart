import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
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
  /// [dio] 可选注入，供单测使用；不传时用 [createAppHttpClient] 构造。
  /// `preferTunnel: true`——GitHub 的发布 API 在部分受限地区跟订阅源一样
  /// 可能被墙，优先经本地 mixed 代理端口发出请求，失败（未连接 VPN /
  /// sing-box 未启动）时自动降级直连，跟"不依赖用户已连接 VPN"并不矛盾：
  /// 未连接时这一步只是快速失败（本地端口无人监听，连接被拒绝几乎零延迟），
  /// 照样立刻降级直连，跟直接强制直连相比没有额外代价，但连接着 VPN 时能
  /// 覆盖"GitHub 本身也被墙"的场景。[mixedPort] 同理，只在 [dio] 未提供时
  /// 生效。
  static Future<String?> checkOnce(
    SharedPreferences prefs, {
    Dio? dio,
    int mixedPort = kDefaultMixedPort,
  }) async {
    if (_disabled || _repoSlug.isEmpty) return null;

    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < _checkIntervalMs) {
      return _compareToCurrentVersion(prefs.getString(_latestTagKey));
    }

    final client =
        dio ??
        createAppHttpClient(
          preferTunnel: true,
          mixedPort: mixedPort,
          receiveTimeout: const Duration(seconds: 10),
        );
    try {
      final resp = await client.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$_repoSlug/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
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
  final mixedPort = ref.read(networkSettingsProvider).mixedPort;
  return UpdateChecker.checkOnce(prefs, mixedPort: mixedPort);
});
