import 'dart:io';

/// sing-box 内核启动时使用的全局默认配置。
///
/// 切换"全局/智能"模式时复用此函数。
/// [executeConfigAsIs] = true → 全局模式，直接使用原始配置；
/// [executeConfigAsIs] = false → 智能模式，附加中国直连分流规则。
Map<String, dynamic> getDefaultConfigOptions({bool executeConfigAsIs = false}) {
  final rules = executeConfigAsIs
      ? <Map<String, dynamic>>[]
      : <Map<String, dynamic>>[
          {
            'domains': 'domain:.cn,geosite:cn',
            'ip': 'geoip:cn',
            'outbound': 'bypass',
          },
        ];

  // 移动端走 VpnService 接管流量 → TUN 必开、系统代理设置不可用（需 root）。
  // 桌面端反过来：系统代理设置 OK，TUN 默认关（需要 admin/root 才能 setup）。
  final isMobile = Platform.isAndroid || Platform.isIOS;

  return {
    'region': executeConfigAsIs ? 'other' : 'cn',
    'block-ads': false,
    'execute-config-as-is': executeConfigAsIs,
    'log-level': 'warn',
    'resolve-destination': false,
    'ipv6-mode': 'ipv4_only',
    'remote-dns-address': 'udp://1.1.1.1',
    'remote-dns-domain-strategy': '',
    'direct-dns-address': '1.1.1.1',
    'direct-dns-domain-strategy': '',
    'mixed-port': 2080,
    'tproxy-port': 2081,
    'local-dns-port': 6450,
    'tun-implementation': 'mixed',
    'mtu': 9000,
    'strict-route': true,
    'connection-test-url': 'http://connectivitycheck.gstatic.com/generate_204',
    'url-test-interval': 600,
    'enable-clash-api': true,
    'clash-api-port': 6756,
    'enable-tun': isMobile,
    'enable-tun-service': false,
    'set-system-proxy': !isMobile,
    'bypass-lan': false,
    'allow-connection-from-lan': false,
    'enable-fake-dns': false,
    'enable-dns-routing': true,
    'independent-dns-cache': true,
    'rules': rules,
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
