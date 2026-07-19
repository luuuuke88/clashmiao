import 'dart:io';

import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/features/profile/model/advanced_config.dart';

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
///
/// [advancedConfig] 当前激活订阅的 per-profile 高级配置。Fragment 在 TLS
/// 拨号层全局生效，由内核按 `tls-tricks` 应用；Mux 不走这里（multiplex 由
/// RuntimeConfigBuilder 注入各 outbound，避免内核与 runtime config 双写）。
Map<String, dynamic> getDefaultConfigOptions({
  bool executeConfigAsIs = false,
  NetworkSettings? settings,
  AdvancedConfig? advancedConfig,
}) {
  // 移动端走 VpnService 接管流量 → TUN 必开、系统代理设置不可用（需 root）。
  // 桌面端反过来：系统代理设置 OK，TUN 默认关（需要 admin/root 才能 setup）。
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final s = settings ?? const NetworkSettings();
  // 移动端 TUN 永远开（不允许 user 关，否则没流量入口）；
  // 桌面端 TUN 默认关，由用户决定要不要开（需要 root）。
  final enableTunFinal = isMobile ? true : s.enableTun;
  // 移动端 system-proxy 始终 false（不可用）；桌面端按用户开关。
  // 例外：CLASHMIAO_TEST_SUB_URL 有值时（CI smoke）强制 false，
  // 因为 GHA Linux runner 没 GNOME session，sing-box 调 gsettings 会
  // 死在 "set system proxy: gsettings ... exit status 1"。smoke 用
  // curl --proxy 127.0.0.1:2080 直接走 mixed inbound 不需要 system proxy。
  final isSmoke =
      (Platform.environment['CLASHMIAO_TEST_SUB_URL'] ?? '').isNotEmpty;
  final setSystemProxyFinal = (isMobile || isSmoke) ? false : s.setSystemProxy;

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
    'block-ads': s.blockAds,
    'log-level': s.logLevel,
    'resolve-destination': s.resolveDestination,
    'ipv6-mode': s.ipv6Mode,
    'remote-dns-address': s.remoteDnsAddress,
    'remote-dns-domain-strategy': s.remoteDnsDomainStrategy,
    'direct-dns-address': s.directDnsAddress,
    'direct-dns-domain-strategy': s.directDnsDomainStrategy,
    'mixed-port': s.mixedPort,
    'tproxy-port': s.tproxyPort,
    'local-dns-port': s.localDnsPort,
    'tun-implementation': s.tunImplementation,
    'mtu': s.mtu,
    'strict-route': s.strictRoute,
    'connection-test-url': s.connectionTestUrl,
    'url-test-interval': s.urlTestIntervalSeconds,
    'enable-clash-api': true,
    'clash-api-port': s.clashApiPort,
    'enable-tun': enableTunFinal,
    'enable-tun-service': false,
    'set-system-proxy': setSystemProxyFinal,
    'bypass-lan': s.bypassLan,
    'allow-connection-from-lan': s.allowConnectionFromLan,
    'enable-fake-dns': s.enableFakeDns,
    'enable-dns-routing': s.enableDnsRouting,
    'independent-dns-cache': s.independentDnsCache,
    'rules': <Map<String, dynamic>>[],
    'mux': {
      'enable': false,
      'padding': s.muxPadding,
      'max-streams': 8,
      'protocol': 'h2mux',
    },
    'tls-tricks': {
      'enable-fragment':
          (advancedConfig?.fragmentEnabled ?? false) || s.enableTlsFragment,
      'fragment-size': (advancedConfig?.fragmentRange?.isNotEmpty == true)
          ? advancedConfig!.fragmentRange!
          : (advancedConfig?.fragmentEnabled == true
                ? '10-100'
                : s.tlsFragmentSize),
      'fragment-sleep': s.tlsFragmentSleep,
      'mixed-sni-case': s.enableTlsMixedSniCase,
      'enable-padding': s.enableTlsPadding,
      'padding-size': s.tlsPaddingSize,
    },
    'warp': {
      'enable': s.enableWarp,
      // 'proxyOverWarp'/'warpOverProxy' 是 Dart 侧 UI 用的驼峰枚举串
      // （见 network_settings.dart 的 _validWarpDetourModes），native 侧
      // 期望 snake_case 的 'proxy_over_warp'/'warp_over_proxy'。
      'mode': s.warpDetourMode == 'warpOverProxy'
          ? 'warp_over_proxy'
          : 'proxy_over_warp',
      'wireguard-config': s.warpWireguardConfig,
      'license-key': s.warpLicenseKey,
      'account-id': s.warpAccountId,
      'access-token': s.warpAccessToken,
      'clean-ip': s.warpCleanIp,
      'clean-port': s.warpPort,
      'noise': s.warpNoise,
      'noise-size': s.warpNoiseSize,
      'noise-delay': s.warpNoiseDelay,
      'noise-mode': s.warpNoiseMode,
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
