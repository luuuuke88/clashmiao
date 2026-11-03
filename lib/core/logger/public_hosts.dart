// 日志脱敏的主机白名单：只有这里列出的**公共、非用户**主机，才允许出现在
// app.log / 崩溃上报里；其余主机（订阅面板、节点服务器、自建 DNS……）一律
// 视为用户数据，由 `redactLogText` 整条遮盖。
//
// 白名单来源：
// - 固定的公共域名：GitHub（更新检查与下载走 `api.github.com`、`github.com`、
//   `*.githubusercontent.com` 的发布资源，按「等于或是子域」匹配）。
// - 官网只放行**精确**的 `clashmiao.com` 与 `www.clashmiao.com`，**不含**其它子
//   域：官方订阅面板可能就部署在某个子域上，它的订阅地址（路径里的短 token）
//   必须遮盖。
// - 公共探测地址：隧道连通性探测与出口 IP 查询用的固定第三方主机（精确匹配）。
// - 编译期常量：`core/env/build_config.dart` 里的外链型参数（源码仓库、隐私
//   政策、服务条款、更新清单、Geo 规则库 CDN、频道地址）。它们是发布构建时
//   写死的公共地址，不是用户输入，所以从常量推导而不是在这里再抄一份。
// - 本机回环（localhost / 127.0.0.0/8 / ::1）：本地内核接口与代理端口，
//   排障需要且不指向任何人。
//
// 主机放行只是第一道：**多租户主机**（GitHub、`*.githubusercontent.com`，以及
// 构建期外链里的 CDN 等）上谁都能托管订阅（`raw.githubusercontent.com/某人/仓库/
// main/sub.yaml`、`github.com/某人/sub`、gist），所以这些主机还要看路径：
// - 本项目自己的仓库路径（[kOwnRepoSlug]），或构建期常量里某条 URL 的路径前缀
//   （更新清单、Geo 规则库下载地址，按「等于或其下」匹配）：保留主机 + 路径；
// - 对象存储 / 发布资源主机（路径是不透明 ID）：只保留 scheme + 主机，路径丢掉；
// - 其余：整条当用户数据。
// 官网、探测地址、本机回环是单租户 / 自己控制的主机，保留主机 + 路径。
// 判定入口是 [publicUrlAccess]；[isPublicHost] 只管裸主机名（`host:port`、
// `address = host` 这类，不带路径）。
//
// 注意：运行时由用户填写的地址（自定义 Geo 下载地址、自建 DNS……）不在白名单里。

import 'package:clashmiao/core/env/build_config.dart';
import 'package:flutter/foundation.dart';

/// 按「等于它或是它的子域」匹配的公共域名。
const Set<String> kPublicHostSuffixes = {'github.com', 'githubusercontent.com'};

/// 只按**精确**主机匹配的公共主机。官网不放行子域（订阅面板可能在子域上）；
/// 探测主机是固定的第三方服务。
///
/// 这是一份策略清单，字面量写在这里；探测主机与代码里实际使用的地址是否一致，
/// 由 `test/core/logger/log_redactor_allowlist_test.dart` 对照下面两处常量检查：
/// - `cp.cloudflare.com`：`kTunnelProbeUrl`
///   （`domain/connection/application/connection_health_monitor.dart`，隧道探测）
/// - `ipwho.is`：`EgressIpService.endpoint`
///   （`domain/connection/application/egress_ip_service.dart`，出口 IP 查询）
const Set<String> kPublicExactHosts = {
  'clashmiao.com',
  'www.clashmiao.com',
  'cp.cloudflare.com',
  'ipwho.is',
};

/// 从若干 URL 字符串里取出主机名（小写）。空串、解析失败、没有主机的忽略。
Set<String> publicHostsFromUrls(Iterable<String> urls) {
  final hosts = <String>{};
  for (final url in urls) {
    if (url.isEmpty) continue;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isNotEmpty) hosts.add(host);
  }
  return hosts;
}

/// 构建期注入 / 兜底的公共外链，来自 `build_config.dart` 的常量（更新检查还会
/// 请求 `api.github.com/repos/<githubRepoSlug>/releases/latest`，一并算进来）。
List<String> _defaultCompiledUrls() => [
  githubRepoUrl,
  kDefaultPrivacyPolicyUrl,
  privacyPolicyUrl,
  termsAndConditionsUrl,
  updateManifestUrl,
  geoipCdnUrl,
  geositeCdnUrl,
  telegramChannelUrl,
  if (githubRepoSlug.isNotEmpty)
    'https://api.github.com/repos/$githubRepoSlug/releases/latest',
];

/// 测试里替换「构建期外链」；传 null 恢复成 `build_config.dart` 的常量。
@visibleForTesting
void debugOverrideCompiledPublicUrls(Iterable<String>? urls) {
  _compiled = _CompiledUrls(urls ?? _defaultCompiledUrls());
}

_CompiledUrls _compiled = _CompiledUrls(_defaultCompiledUrls());

Set<String> get _compiledPublicHosts => _compiled.hosts;

/// 当前构建的公共主机白名单（只读视图，供测试断言）。
Set<String> get compiledPublicHosts => Set.unmodifiable(_compiledPublicHosts);

final RegExp _ipv4Loopback = RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

/// [host] 是否本机回环。接受带方括号的 IPv6 字面量。
bool isLoopbackHost(String host) {
  var h = host.toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h == 'localhost' ||
      h == '::1' ||
      h == '0:0:0:0:0:0:0:1' ||
      _ipv4Loopback.hasMatch(h);
}

/// [host] 是否在白名单里（公共域名及其子域、构建期外链主机、本机回环）。
bool isPublicHost(String host) {
  var h = host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (h.isEmpty) return false;
  if (isLoopbackHost(h)) return true;
  if (kPublicExactHosts.contains(h) || _compiledPublicHosts.contains(h)) {
    return true;
  }
  for (final suffix in kPublicHostSuffixes) {
    if (h == suffix || h.endsWith('.$suffix')) return true;
  }
  return false;
}

// ─── 带路径的放行判定 ────────────────────────────────────────────────

/// 本项目自己的公开仓库（`owner/repo`）。多租户主机上只有这个路径下的 URL
/// 无条件放行；是公开信息，不是用户数据。
const String kOwnRepoSlug = 'luuuuke88/clashmiao';

/// 路径是不透明 ID（对象存储、发布资源）的 GitHub 主机：只保留 scheme + 主机。
const Set<String> kOpaquePathHosts = {
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
  'github-releases.githubusercontent.com',
};

/// 一条 URL 在日志里能保留多少。
enum PublicUrlAccess {
  /// 整条当用户数据，换成占位符。
  none,

  /// 只保留 scheme + 主机（+ 端口），路径丢掉。
  hostOnly,

  /// 保留 scheme + 主机 + 路径（查询串、片段照例丢掉）。
  hostAndPath,
}

/// 构建期外链解析后的主机集合与「主机 → 路径前缀」。
class _CompiledUrls {
  _CompiledUrls(Iterable<String> urls) {
    for (final url in urls) {
      if (url.isEmpty) continue;
      final uri = Uri.tryParse(url);
      final host = uri?.host.toLowerCase() ?? '';
      if (uri == null || host.isEmpty) continue;
      hosts.add(host);
      final prefix = _normalizedPrefix(uri.path);
      if (prefix == null) continue;
      // GitHub 系主机的第一段是用户 / 组织：至少要「用户/仓库」两段，免得一条
      // 形如 `/某人` 的外链把整个命名空间放行。
      final minSegments = _isGithubFamily(host) ? 2 : 1;
      if (prefix.split('/').length - 1 < minSegments) continue;
      (prefixes[host] ??= <String>[]).add(prefix);
    }
  }

  final Set<String> hosts = {};
  final Map<String, List<String>> prefixes = {};
}

/// 小写、去掉末尾斜杠；空路径与 `/` 返回 null。
String? _normalizedPrefix(String path) {
  var p = path.toLowerCase();
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p.isEmpty ? null : p;
}

bool _isGithubFamily(String host) {
  for (final suffix in kPublicHostSuffixes) {
    if (host == suffix || host.endsWith('.$suffix')) return true;
  }
  return false;
}

/// 路径本身是否「规矩」：不含百分号编码、反斜杠、`.` / `..` / 空段。编码或点段
/// 可以把别人的路径伪装成前缀之下，规矩之外一律不放行。
bool _isPlainPath(String path) {
  if (path.contains('%') || path.contains('\\')) return false;
  final segments = path.split('/');
  // 第 0 段是前导 `/` 之前的空串；末尾允许一个空段（`/a/b/`）。
  for (var i = 1; i < segments.length; i++) {
    final segment = segments[i];
    if (segment == '.' || segment == '..') return false;
    if (segment.isEmpty && i != segments.length - 1) return false;
  }
  return true;
}

bool _underPrefix(String lowerPath, String prefix) =>
    lowerPath == prefix || lowerPath.startsWith('$prefix/');

/// 本项目自己仓库在各个 GitHub 主机上的路径前缀。
String? _ownRepoPrefix(String host) {
  final slug = kOwnRepoSlug.toLowerCase();
  if (host == 'api.github.com') return '/repos/$slug';
  if (host == 'github.com' ||
      host == 'codeload.github.com' ||
      host == 'raw.githubusercontent.com') {
    return '/$slug';
  }
  return null;
}

/// [host] 上路径为 [path] 的 URL 在日志里能保留多少（主机名按 [isPublicHost]
/// 的口径归一化；[path] 是 URL 的原始路径，不含查询串）。
PublicUrlAccess publicUrlAccess(String host, String path) {
  var h = host.toLowerCase();
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  if (!isPublicHost(h)) return PublicUrlAccess.none;

  // 单租户 / 自己控制的主机：保留主机 + 路径。
  if (isLoopbackHost(h) || kPublicExactHosts.contains(h)) {
    return PublicUrlAccess.hostAndPath;
  }
  // 路径是不透明 ID 的主机：路径丢掉。
  if (kOpaquePathHosts.contains(h)) return PublicUrlAccess.hostOnly;

  // 其余是多租户主机（GitHub 系、构建期外链里的 CDN 等）：看路径前缀。
  if (path.isEmpty || path == '/') return PublicUrlAccess.hostAndPath;
  if (!_isPlainPath(path)) return PublicUrlAccess.none;
  final lower = path.toLowerCase();
  final own = _ownRepoPrefix(h);
  if (own != null && _underPrefix(lower, own)) {
    return PublicUrlAccess.hostAndPath;
  }
  for (final prefix in _compiled.prefixes[h] ?? const <String>[]) {
    if (_underPrefix(lower, prefix)) return PublicUrlAccess.hostAndPath;
  }
  return PublicUrlAccess.none;
}
