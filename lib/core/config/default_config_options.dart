import 'dart:io';

import 'package:clashmiao/core/settings/network_settings.dart';

/// sing-box 内核启动时使用的全局默认配置（上游 libcore fork 的 `configOptions`）。
///
/// 注意：智能 / 全局分流由 `RuntimeConfigBuilder` 在 connect 时
/// 现场写到 runtime-config.json，**不**依赖这里的 fork-side `region` / `rules`。
///
/// [executeConfigAsIs] 现在只用于 Dart 端记录用户选择，
/// 不再走 fork 的 cn 路径（避免 fork 强制 append 中国大陆下载不动的 remote rule-set）。
///
/// [settings] 让用户从 SettingsPage 调的 port / TUN / system-proxy / LAN
/// 等开关真正生效。`null` 时回退到平台默认值（旧行为）。
Map<String, dynamic> getDefaultConfigOptions({
  bool executeConfigAsIs = false,
  NetworkSettings? settings,
}) {
  // 移动端走 VpnService 接管流量 → TUN 必开、系统代理设置不可用（需 root）。
  // 桌面端反过来：系统代理设置 OK，TUN 默认关（需要 admin/root 才能 setup）。
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final s = settings ?? const NetworkSettings();
  // 移动端 TUN 永远开（不允许 user 关，否则没流量入口）；
  // 桌面端 TUN 默认关，由用户决定要不要开（需要 root）。
  final enableTunFinal = isMobile ? true : s.enableTun;
  // 移动端 system-proxy 始终 false（不可用）；桌面端按用户开关。
  final setSystemProxyFinal = isMobile ? false : s.setSystemProxy;

  return {
    // region 永远 'other'：sing-box 1.8 fork（上游 libcore fork）在 region != 'other'
    // 时会强制 append 一个 remote rule-set，URL 指向 上游 geo CDN，中国大陆 GFW 阻断
    // 让 sing-box 启动时 routing 不完整。我们改用 Dart 端注入 local rule-set
    // （RuntimeConfigBuilder）。
    'region': 'other',
    // 不让 fork 自己注入 bypass rules，路由完全交给 RuntimeConfigBuilder。
    'execute-config-as-is': true,
    // 关键：让 fork 用 profile 自带的 inbounds/dns/route，而不是自己 rebuild
    // 一份强制走 udp://1.1.1.1 / 强制 append remote rule-set 的 DNS 配置。
    'enable-full-config': true,
    'block-ads': false,
    'log-level': 'warn',
    'resolve-destination': false,
    'ipv6-mode': 'ipv4_only',
    'remote-dns-address': s.remoteDnsAddress,
    'remote-dns-domain-strategy': '',
    'direct-dns-address': '1.1.1.1',
    'direct-dns-domain-strategy': '',
    'mixed-port': s.mixedPort,
    'tproxy-port': 2081,
    'local-dns-port': 6450,
    'tun-implementation': 'mixed',
    'mtu': 9000,
    'strict-route': true,
    'connection-test-url': 'http://connectivitycheck.gstatic.com/generate_204',
    'url-test-interval': 600,
    'enable-clash-api': true,
    'clash-api-port': 6756,
    'enable-tun': enableTunFinal,
    'enable-tun-service': false,
    'set-system-proxy': setSystemProxyFinal,
    'bypass-lan': false,
    'allow-connection-from-lan': s.allowConnectionFromLan,
    'enable-fake-dns': false,
    'enable-dns-routing': s.enableDnsRouting,
    'independent-dns-cache': true,
    'rules': <Map<String, dynamic>>[],
    'mux': {
      'enable': false,
      'padding': false,
      'max-streams': 8,
      'protocol': 'h2mux',
    },
    'tls-tricks': {
      'enable-fragment': false,
      'fragment-size': '10-100',
      'fragment-sleep': '50-200',
      'mixed-sni-case': false,
      'enable-padding': false,
      'padding-size': '100-200',
    },
    'warp': {
      'enable': false,
      'mode': 'proxy_over_warp',
      'wireguard-config': '',
      'license-key': '',
      'account-id': '',
      'access-token': '',
      'clean-ip': '',
      'clean-port': 0,
      'noise': '10-15',
      'noise-size': '5-10',
      'noise-delay': '1-1',
      'noise-mode': 'm4',
    },
    'warp2': {
      'enable': false,
      'mode': 'proxy_over_warp',
      'wireguard-config': '',
      'license-key': '',
      'account-id': '',
      'access-token': '',
      'clean-ip': '',
      'clean-port': 0,
      'noise': '10-15',
      'noise-size': '5-10',
      'noise-delay': '1-1',
      'noise-mode': 'm4',
    },
  };
}
