import 'dart:io';

import 'package:clashmiao/domain/config/data/cn_direct_rules.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/config/model/advanced_config.dart';

/// 内核配置构建器（`BuildConfig`）的全局选项（`configOptions`）。
///
/// 智能 / 全局分流由 [isSmart] 驱动的 `rules` 字段决定——**不是**
/// `RuntimeConfigBuilder` 写进 runtime-config.json 的 profile `route` 块：
/// 构建器对订阅自带的 `dns` / `route` / `inbounds` 一律丢弃重建，DNS 与路由
/// 只由这里的选项推出。所以中国 IP / 域名直连的数据必须通过 `rules` 注入。
///
/// [executeConfigAsIs] 只用于 Dart 端记录用户选择，内核不读它。
///
/// [settings] 让用户从 SettingsPage 调的 port / TUN / system-proxy / LAN
/// 等开关真正生效。`null` 时回退到平台默认值（旧行为）。
///
/// [advancedConfig] 当前激活订阅的 per-profile 高级配置：`remoteDnsOverride`
/// 非空时覆盖全局的远程 DNS 地址；TLS 分片在拨号层全局生效，由构建器按
/// `tls-tricks.enable-fragment` 兑现；Mux 不走这里（multiplex 由
/// RuntimeConfigBuilder 注入各 outbound，避免内核与 runtime config 双写）。
///
/// 键集合是跨语言契约：Dart 产生的每个键 Go 侧都必须认识（`keys.txt`、
/// `dart_fixture_test.go` 把关）。新增键要同时改 Go 的选项模型。
Map<String, dynamic> getDefaultConfigOptions({
  bool executeConfigAsIs = false,
  bool isSmart = false,
  NetworkSettings? settings,
  AdvancedConfig? advancedConfig,
}) {
  // 移动端走 VpnService 接管流量 → TUN 必开、系统代理设置不可用（需 root）。
  // 桌面端反过来：系统代理设置 OK，TUN 默认关（需要 admin/root 才能 setup）。
  final isMobile = serviceModePlatform != ServiceModePlatform.desktop;
  final s = settings ?? const NetworkSettings();
  // Android 上 enable-tun 就是服务模式（VPN / 仅线路）：原生协调器按它选择
  // Service 类，形态随请求走、进 revision——连接中切模式才会真的换类。iOS 恒为
  // true；桌面端按用户开关。口径见 service_mode.dart。
  final enableTunFinal = kernelEnableTun(s);
  // 移动端 system-proxy 始终 false（不可用）；桌面端按用户开关。
  // 例外：CLASHMIAO_TEST_SUB_URL 有值时（CI smoke）强制 false，
  // 因为 GHA Linux runner 没 GNOME session，sing-box 调 gsettings 会
  // 死在 "set system proxy: gsettings ... exit status 1"。smoke 用
  // curl --proxy 127.0.0.1:2080 直接走 mixed inbound 不需要 system proxy。
  final override = advancedConfig?.remoteDnsOverride;
  final remoteDnsAddress = (override != null && override.isNotEmpty)
      ? override
      : s.remoteDnsAddress;
  final isSmoke =
      (Platform.environment['CLASHMIAO_TEST_SUB_URL'] ?? '').isNotEmpty;
  final setSystemProxyFinal = (isMobile || isSmoke) ? false : s.setSystemProxy;

  return {
    // region 永远 'other'：内核只认 other（非 other 会被忽略并给 warning）；
    // 国内直连数据由下面的 `rules` 注入，不依赖任何远程规则集。
    'region': 'other',
    // 内核不读这个键，只用于 Dart 端记录用户选择。
    'execute-config-as-is': executeConfigAsIs,
    // 内核忽略完整配置里的入站；dns 与 route 块一律丢弃重建：真正生效的 DNS 是
    // 下面的 remote-/direct-dns-address 加分流规则推出的 DNS 规则——智能分流里
    // 命中国内直连规则的域名走 dns-direct，地址就是 direct-dns-address。
    'enable-full-config': true,
    'block-ads': s.blockAds,
    'log-level': s.logLevel,
    'resolve-destination': s.resolveDestination,
    'ipv6-mode': s.ipv6Mode,
    // 订阅级覆盖优先于全局设置（高级配置里的 remoteDnsOverride）。
    'remote-dns-address': remoteDnsAddress,
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
    // isSmart 时强制开：下面 rules 里的中国 IP/域名直连规则要真正生效，
    // 依赖内核的 DNS 路由开关（DNS 规则的应用整段受它控制）——不能让用户关闭的
    // "DNS 路由"设置连带把智能分流的直连规则也一起废掉。
    'enable-dns-routing': isSmart || s.enableDnsRouting,
    'independent-dns-cache': s.independentDnsCache,
    // 智能分流的全部数据都在这里注入：明文列表，不依赖任何远程规则集——
    // 数据来源见 `cn_direct_rules.dart` 的文件头。
    //
    // 前缀是内核规则解析认的语法：`full:` 进 Domain（精确匹配），
    // `domain:` 进 DomainSuffix（后缀匹配），`regexp:` 进 DomainRegex。语义
    // 不同，不能混用。正则清单是排除表改写出来的"跳过谷歌系域名的宽后缀"
    // （见 cn_direct_rules.dart 文件头），少了它顶级域 `cn` 下的直连就没了。
    'rules': isSmart
        ? <Map<String, dynamic>>[
            {'ip': cnDirectCidrRanges.join(','), 'outbound': 'bypass'},
            {
              'domains': [
                ...cnDirectDomains.map((d) => 'full:$d'),
                ...cnDirectDomainSuffixes.map((d) => 'domain:$d'),
                ...cnDirectDomainRegexes.map((r) => 'regexp:$r'),
              ].join(','),
              'outbound': 'bypass',
            },
          ]
        : <Map<String, dynamic>>[],
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
