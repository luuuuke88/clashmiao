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
// 白名单只决定**主机**能不能出现在日志里；不管哪个主机，URL 的路径、查询串、片段
// 一律不保留（见 `log_redactor.dart`）：谁都能在 GitHub 上托管订阅，官网路径下也
// 可能是订阅地址，脱敏器无从知道来源。
//
// 注意：运行时由用户填写的地址（自定义 Geo 下载地址、自建 DNS……）不在白名单里。

import 'package:clashmiao/core/env/build_config.dart';

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

final Set<String> _compiledPublicHosts = publicHostsFromUrls(
  _defaultCompiledUrls(),
);

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
