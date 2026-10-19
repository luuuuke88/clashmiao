import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/http_client/app_http_client.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 见 `core/env/build_config.dart`：所有编译期参数集中声明在那里。
const _repoSlug = githubRepoSlug;
const _disabled = bool.fromEnvironment('CLASHMIAO_DISABLE_UPDATE_CHECK');
const _checkIntervalMs = 24 * 60 * 60 * 1000;
const _lastCheckKey = 'update_last_check_ms';
const _latestTagKey = 'update_latest_tag';

/// 一次检查更新的结论。
///
/// [UpdateChecker.checkOnce] 只回 `String?`，把「已是最新」和「检查失败」
/// 都折成 null——启动时的静默检查正好需要这种折叠（两种情况都什么都不弹），
/// 但用户手动点「检查更新」时必须能分清：失败却报「已是最新版本」是在骗人。
enum UpdateCheckStatus {
  /// 确认没有比当前更新的版本。
  upToDate,

  /// 有新版本，[UpdateCheckResult.tag] 非空。
  available,

  /// 没能得到结论：所有来源都失败，或检查被禁用 / 没有任何来源可问。
  /// 此时无法断言「已是最新」。
  failed,
}

class UpdateCheckResult {
  const UpdateCheckResult._(this.status, [this.tag]);

  const UpdateCheckResult.upToDate() : this._(UpdateCheckStatus.upToDate);
  const UpdateCheckResult.available(String tag)
    : this._(UpdateCheckStatus.available, tag);
  const UpdateCheckResult.failed() : this._(UpdateCheckStatus.failed);

  final UpdateCheckStatus status;

  /// 仅 [UpdateCheckStatus.available] 时有值，形如 `v1.2.3`。
  final String? tag;
}

/// 官网发布的版本清单。
///
/// 优先问它、而不是直接问 GitHub API，原因有三：
///   - 未认证的 GitHub API 是 60 次/小时/**IP**。同一运营商 NAT 后面的用户
///     共用出口 IP，用户一多就集体被限流；而限流的表现是"检查更新永远失败"，
///     完全静默，没人会报这个 bug。
///   - GitHub API 在部分地区本身就不稳定，而"检查更新"恰恰是用户还没连上
///     隧道时最可能触发的动作。
///   - 官网在 CDN 上，边缘缓存、全球可达，且随发版自动重建，内容不会滞后。
///
/// GitHub 仍然作为兜底保留：官网挂了不该让这个功能整个失效。
///
/// 地址来自编译期参数 `UPDATE_MANIFEST_URL`（见 build_config.dart），空表示
/// 这条来源不可用——跟 GITHUB_REPO_SLUG 是同一套约定。
class UpdateChecker {
  /// 静默检查用：有新版本返回其 tag，其余（已是最新 / 失败）一律 null。
  /// 需要区分失败的调用方用 [check]。
  static Future<String?> checkOnce(
    SharedPreferences prefs, {
    Dio? dio,
    int mixedPort = kDefaultMixedPort,
    String manifestUrl = updateManifestUrl,
    String? githubApiUrl,
  }) async {
    final result = await check(
      prefs,
      dio: dio,
      mixedPort: mixedPort,
      manifestUrl: manifestUrl,
      githubApiUrl: githubApiUrl,
    );
    return result.tag;
  }

  /// [dio] 可选注入，供单测使用；不传时用 [createAppHttpClient] 构造。
  /// `preferTunnel: true`——发布信息在部分受限地区跟订阅源一样可能被墙，
  /// 优先经本地 mixed 代理端口发出请求，失败（未连接 VPN / sing-box 未启动）
  /// 时自动降级直连，跟"不依赖用户已连接 VPN"并不矛盾：未连接时这一步只是
  /// 快速失败（本地端口无人监听，连接被拒绝几乎零延迟），照样立刻降级直连，
  /// 跟直接强制直连相比没有额外代价，但连接着 VPN 时能覆盖"源站也被墙"的
  /// 场景。[mixedPort] 同理，只在 [dio] 未提供时生效。
  ///
  /// [manifestUrl] / [githubApiUrl] 仅供测试指向本地假服务器。
  static Future<UpdateCheckResult> check(
    SharedPreferences prefs, {
    Dio? dio,
    int mixedPort = kDefaultMixedPort,
    String manifestUrl = updateManifestUrl,
    String? githubApiUrl,
  }) async {
    // 两条来源都没配置就直接返回——别去打一个不存在的地址。这里无法得出
    // 「已是最新」的结论，所以是 failed 而不是 upToDate。
    if (_disabled) return const UpdateCheckResult.failed();
    if (manifestUrl.isEmpty && _repoSlug.isEmpty && githubApiUrl == null) {
      return const UpdateCheckResult.failed();
    }

    final last = prefs.getInt(_lastCheckKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cachedTag = prefs.getString(_latestTagKey);
    // 缓存里没有 tag（例如时间戳被写过但 tag 丢了）不能当「已是最新」。
    if (now - last < _checkIntervalMs && cachedTag != null) {
      return _compareToCurrentVersion(cachedTag);
    }

    final client =
        dio ??
        createAppHttpClient(
          preferTunnel: true,
          mixedPort: mixedPort,
          receiveTimeout: const Duration(seconds: 10),
        );

    // 先问官网，失败再问 GitHub。两条路任何一条成功就落库并返回。
    final tag =
        (manifestUrl.isEmpty
            ? null
            : await _fetchTag(
                client,
                manifestUrl,
                (d) => d['tag'] as String?,
              )) ??
        await _fetchGithubTag(client, githubApiUrl);

    if (tag != null) {
      await prefs.setString(_latestTagKey, tag);
      await prefs.setInt(_lastCheckKey, now);
      return _compareToCurrentVersion(tag);
    }
    return const UpdateCheckResult.failed();
  }

  static Future<String?> _fetchGithubTag(Dio client, String? overrideUrl) {
    final url =
        overrideUrl ??
        (_repoSlug.isEmpty
            ? null
            : 'https://api.github.com/repos/$_repoSlug/releases/latest');
    if (url == null) return Future.value(null);
    return _fetchTag(
      client,
      url,
      (d) => d['tag_name'] as String?,
      headers: const {'Accept': 'application/vnd.github.v3+json'},
    );
  }

  /// 拉一个 JSON 并按 [pick] 取出 tag。任何失败都返回 null，让调用方走下一条路。
  static Future<String?> _fetchTag(
    Dio client,
    String url,
    String? Function(Map<String, dynamic>) pick, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await client.get<Map<String, dynamic>>(
        url,
        options: Options(headers: headers),
      );
      final data = resp.data;
      if (data == null) return null;
      final tag = pick(data);
      // 空字符串跟拿不到是一回事，别让它当成"有效结果"往下传
      return (tag != null && tag.isNotEmpty) ? tag : null;
    } catch (_) {
      // 网络失败静默处理——检查更新失败不该打扰用户
      return null;
    }
  }

  static Future<UpdateCheckResult> _compareToCurrentVersion(
    String latestTag,
  ) async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final latest = latestTag.replaceFirst('v', '');
    return _isNewer(latest, current)
        ? UpdateCheckResult.available(latestTag)
        : const UpdateCheckResult.upToDate();
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
