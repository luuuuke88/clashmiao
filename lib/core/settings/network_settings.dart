import 'dart:convert';

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 网络设置 持久化层。
///
/// 这里的字段都会写到 SharedPreferences，并通过 ConnectionController 触发
/// `boxService.changeConfigOptions(...)` 把变更推给 sing-box。
class NetworkSettings {
  const NetworkSettings({
    this.mixedPort = 2080,
    this.region = 'other',
    this.blockAds = false,
    this.logLevel = 'warn',
    this.bypassLan = false,
    this.resolveDestination = false,
    this.ipv6Mode = 'ipv4_only',
    this.setSystemProxy = true,
    this.enableTun = false,
    this.allowConnectionFromLan = false,
    this.enableDnsRouting = true,
    this.enableFakeDns = false,
    this.independentDnsCache = true,
    this.remoteDnsDomainStrategy = '',
    this.directDnsAddress = '1.1.1.1',
    this.directDnsDomainStrategy = '',
    this.tunImplementation = 'mixed',
    this.strictRoute = true,
    // mtu/clashApiPort/tproxyPort/localDnsPort 默认值沿用此前
    // default_config_options.dart 里的硬编码常量（而非参照项目的原始默认值），
    // 避免这次"硬编码转可配置字段"的重构悄悄改变现有用户的运行时行为——
    // 参照项目对应默认值是 mtu=9000（一致）、clash-api-port=16756、
    // tproxy-port=12335、local-dns-port=16450（端口号不同是因为 clashmiao
    // 一直用更低位的端口段，与 mixedPort=2080 保持同一序列）。
    this.mtu = 9000,
    this.clashApiPort = 6756,
    this.tproxyPort = 2081,
    this.localDnsPort = 6450,
    this.enableTlsFragment = false,
    this.tlsFragmentSize = '10-30',
    // tlsFragmentSleep/tlsPaddingSize 同样沿用此前硬编码值：参照项目默认值
    // 分别是 2-8 / 1-1500，但 clashmiao 一直用 50-200 / 100-200 跑，为避免
    // 行为回归这里保留现状（字段名/校验规则仍对齐参照项目）。
    this.tlsFragmentSleep = '50-200',
    this.enableTlsPadding = false,
    this.enableTlsMixedSniCase = false,
    this.tlsPaddingSize = '100-200',
    this.muxPadding = false,
    this.enableWarp = false,
    this.warpConsentGiven = false,
    this.warpDetourMode = 'proxyOverWarp',
    this.warpLicenseKey = '',
    // 以下 6 个 WARP 噪音混淆默认值对齐参照项目推荐值：空值在 native 层会被
    // 当成"禁用混淆"而非"合理默认"，之前的全空/固定端口偏离了推荐区间。
    this.warpCleanIp = 'auto',
    this.warpPort = 0,
    this.warpNoise = '1-3',
    this.warpNoiseSize = '10-30',
    this.warpNoiseMode = 'm6',
    this.warpNoiseDelay = '10-30',
    this.warpAccountId = '',
    this.warpAccessToken = '',
    this.warpWireguardConfig = '',
    this.connectionTestUrl =
        'http://connectivitycheck.gstatic.com/generate_204',
    this.urlTestIntervalSeconds = 600,
    // DoH 走 TCP，对不支持 UDP 转发的 SS / Trojan 等代理节点也能工作。
    // 用 udp://1.1.1.1 风险：如果代理 outbound 不支持 UDP，DNS 永远超时
    // → Chrome 报 DNS_PROBE_FINISHED_NXDOMAIN。
    this.remoteDnsAddress = 'https://1.1.1.1/dns-query',
  });

  final int mixedPort;
  final String region;
  final bool blockAds;
  final String logLevel;
  final bool bypassLan;
  final bool resolveDestination;
  final String ipv6Mode;
  final bool setSystemProxy;
  final bool enableTun;
  final bool allowConnectionFromLan;
  final bool enableDnsRouting;

  /// sing-box fake-ip DNS（把域名解析成虚假 IP，靠路由层再按域名分流）。
  final bool enableFakeDns;

  /// DNS 缓存是否独立于普通连接缓存（避免污染/被普通缓存驱逐策略影响）。
  final bool independentDnsCache;

  final String remoteDnsAddress;
  final String remoteDnsDomainStrategy;
  final String directDnsAddress;
  final String directDnsDomainStrategy;
  final String tunImplementation;
  final bool strictRoute;

  /// TUN 接口 MTU。
  final int mtu;

  /// sing-box Clash API 监听端口。
  final int clashApiPort;

  /// TProxy 入站端口（Linux 透明代理）。
  final int tproxyPort;

  /// 内置本地 DNS 服务器监听端口。
  final int localDnsPort;

  final bool enableTlsFragment;
  final String tlsFragmentSize;

  /// TLS 分段之间的 sleep 区间（毫秒，"min-max" 格式）。
  final String tlsFragmentSleep;

  final bool enableTlsPadding;

  /// TLS ClientHello SNI 是否使用大小写混合（一种简单的 DPI 规避手段）。
  final bool enableTlsMixedSniCase;

  /// TLS padding 长度区间（字节，"min-max" 格式）。
  final String tlsPaddingSize;

  /// Mux（多路复用）流是否启用 padding。
  final bool muxPadding;

  final bool enableWarp;
  final bool warpConsentGiven;
  final String warpDetourMode;
  final String warpLicenseKey;
  final String warpCleanIp;
  final int warpPort;
  final String warpNoise;
  final String warpNoiseSize;
  final String warpNoiseMode;
  final String warpNoiseDelay;

  /// Cloudflare WARP 账号 ID —— 由 `generateWarpConfig` 生成后写入，
  /// 再次生成时作为 previous-account-id 传给 native 以续用同一账号。
  final String warpAccountId;

  /// 上面账号对应的访问令牌。
  final String warpAccessToken;

  /// WireGuard 端点配置（JSON 字符串），由 `generateWarpConfig` 生成后写入，
  /// 注入运行时配置时原样透传给 native，Dart 侧不解析其内部字段。
  final String warpWireguardConfig;

  final String connectionTestUrl;
  final int urlTestIntervalSeconds;

  NetworkSettings copyWith({
    int? mixedPort,
    String? region,
    bool? blockAds,
    String? logLevel,
    bool? bypassLan,
    bool? resolveDestination,
    String? ipv6Mode,
    bool? setSystemProxy,
    bool? enableTun,
    bool? allowConnectionFromLan,
    bool? enableDnsRouting,
    bool? enableFakeDns,
    bool? independentDnsCache,
    String? remoteDnsAddress,
    String? remoteDnsDomainStrategy,
    String? directDnsAddress,
    String? directDnsDomainStrategy,
    String? tunImplementation,
    bool? strictRoute,
    int? mtu,
    int? clashApiPort,
    int? tproxyPort,
    int? localDnsPort,
    bool? enableTlsFragment,
    String? tlsFragmentSize,
    String? tlsFragmentSleep,
    bool? enableTlsPadding,
    bool? enableTlsMixedSniCase,
    String? tlsPaddingSize,
    bool? muxPadding,
    bool? enableWarp,
    bool? warpConsentGiven,
    String? warpDetourMode,
    String? warpLicenseKey,
    String? warpCleanIp,
    int? warpPort,
    String? warpNoise,
    String? warpNoiseSize,
    String? warpNoiseMode,
    String? warpNoiseDelay,
    String? warpAccountId,
    String? warpAccessToken,
    String? warpWireguardConfig,
    String? connectionTestUrl,
    int? urlTestIntervalSeconds,
  }) {
    return NetworkSettings(
      mixedPort: mixedPort ?? this.mixedPort,
      region: region ?? this.region,
      blockAds: blockAds ?? this.blockAds,
      logLevel: logLevel ?? this.logLevel,
      bypassLan: bypassLan ?? this.bypassLan,
      resolveDestination: resolveDestination ?? this.resolveDestination,
      ipv6Mode: ipv6Mode ?? this.ipv6Mode,
      setSystemProxy: setSystemProxy ?? this.setSystemProxy,
      enableTun: enableTun ?? this.enableTun,
      allowConnectionFromLan:
          allowConnectionFromLan ?? this.allowConnectionFromLan,
      enableDnsRouting: enableDnsRouting ?? this.enableDnsRouting,
      enableFakeDns: enableFakeDns ?? this.enableFakeDns,
      independentDnsCache: independentDnsCache ?? this.independentDnsCache,
      remoteDnsAddress: remoteDnsAddress ?? this.remoteDnsAddress,
      remoteDnsDomainStrategy:
          remoteDnsDomainStrategy ?? this.remoteDnsDomainStrategy,
      directDnsAddress: directDnsAddress ?? this.directDnsAddress,
      directDnsDomainStrategy:
          directDnsDomainStrategy ?? this.directDnsDomainStrategy,
      tunImplementation: tunImplementation ?? this.tunImplementation,
      strictRoute: strictRoute ?? this.strictRoute,
      mtu: mtu ?? this.mtu,
      clashApiPort: clashApiPort ?? this.clashApiPort,
      tproxyPort: tproxyPort ?? this.tproxyPort,
      localDnsPort: localDnsPort ?? this.localDnsPort,
      enableTlsFragment: enableTlsFragment ?? this.enableTlsFragment,
      tlsFragmentSize: tlsFragmentSize ?? this.tlsFragmentSize,
      tlsFragmentSleep: tlsFragmentSleep ?? this.tlsFragmentSleep,
      enableTlsPadding: enableTlsPadding ?? this.enableTlsPadding,
      enableTlsMixedSniCase:
          enableTlsMixedSniCase ?? this.enableTlsMixedSniCase,
      tlsPaddingSize: tlsPaddingSize ?? this.tlsPaddingSize,
      muxPadding: muxPadding ?? this.muxPadding,
      enableWarp: enableWarp ?? this.enableWarp,
      warpConsentGiven: warpConsentGiven ?? this.warpConsentGiven,
      warpDetourMode: warpDetourMode ?? this.warpDetourMode,
      warpLicenseKey: warpLicenseKey ?? this.warpLicenseKey,
      warpCleanIp: warpCleanIp ?? this.warpCleanIp,
      warpPort: warpPort ?? this.warpPort,
      warpNoise: warpNoise ?? this.warpNoise,
      warpNoiseSize: warpNoiseSize ?? this.warpNoiseSize,
      warpNoiseMode: warpNoiseMode ?? this.warpNoiseMode,
      warpNoiseDelay: warpNoiseDelay ?? this.warpNoiseDelay,
      warpAccountId: warpAccountId ?? this.warpAccountId,
      warpAccessToken: warpAccessToken ?? this.warpAccessToken,
      warpWireguardConfig: warpWireguardConfig ?? this.warpWireguardConfig,
      connectionTestUrl: connectionTestUrl ?? this.connectionTestUrl,
      urlTestIntervalSeconds:
          urlTestIntervalSeconds ?? this.urlTestIntervalSeconds,
    );
  }
}

const _kMixedPort = 'clashmiao_mixed_port';
const _kRegion = 'clashmiao_region';
const _kBlockAds = 'clashmiao_block_ads';
const _kLogLevel = 'clashmiao_log_level';
const _kBypassLan = 'clashmiao_bypass_lan';
const _kResolveDestination = 'clashmiao_resolve_destination';
const _kIpv6Mode = 'clashmiao_ipv6_mode';
const _kSetSystemProxy = 'clashmiao_set_system_proxy';
const _kEnableTun = 'clashmiao_enable_tun';
const _kAllowLan = 'clashmiao_allow_lan';
const _kEnableDnsRouting = 'clashmiao_enable_dns_routing';
const _kEnableFakeDns = 'clashmiao_enable_fake_dns';
const _kIndependentDnsCache = 'clashmiao_independent_dns_cache';
const _kRemoteDnsAddress = 'clashmiao_remote_dns_address';
const _kRemoteDnsDomainStrategy = 'clashmiao_remote_dns_domain_strategy';
const _kDirectDnsAddress = 'clashmiao_direct_dns_address';
const _kDirectDnsDomainStrategy = 'clashmiao_direct_dns_domain_strategy';
const _kTunImplementation = 'clashmiao_tun_implementation';
const _kStrictRoute = 'clashmiao_strict_route';
const _kMtu = 'clashmiao_mtu';
const _kClashApiPort = 'clashmiao_clash_api_port';
const _kTproxyPort = 'clashmiao_tproxy_port';
const _kLocalDnsPort = 'clashmiao_local_dns_port';
const _kEnableTlsFragment = 'clashmiao_enable_tls_fragment';
const _kTlsFragmentSize = 'clashmiao_tls_fragment_size';
const _kTlsFragmentSleep = 'clashmiao_tls_fragment_sleep';
const _kEnableTlsPadding = 'clashmiao_enable_tls_padding';
const _kEnableTlsMixedSniCase = 'clashmiao_enable_tls_mixed_sni_case';
const _kTlsPaddingSize = 'clashmiao_tls_padding_size';
const _kMuxPadding = 'clashmiao_mux_padding';
const _kEnableWarp = 'clashmiao_enable_warp';
const _kWarpConsentGiven = 'clashmiao_warp_consent_given';
const _kWarpDetourMode = 'clashmiao_warp_detour_mode';
const _kWarpLicenseKey = 'clashmiao_warp_license_key';
const _kWarpCleanIp = 'clashmiao_warp_clean_ip';
const _kWarpPort = 'clashmiao_warp_port';
const _kWarpNoise = 'clashmiao_warp_noise';
const _kWarpNoiseSize = 'clashmiao_warp_noise_size';
const _kWarpNoiseMode = 'clashmiao_warp_noise_mode';
const _kWarpNoiseDelay = 'clashmiao_warp_noise_delay';
const _kWarpAccountId = 'clashmiao_warp_account_id';
const _kWarpAccessToken = 'clashmiao_warp_access_token';
const _kWarpWireguardConfig = 'clashmiao_warp_wireguard_config';
const _kConnectionTestUrl = 'clashmiao_connection_test_url';
const _kUrlTestIntervalSeconds = 'clashmiao_url_test_interval_seconds';

const _validRegions = {'ir', 'cn', 'ru', 'af', 'id', 'other'};
const _validLogLevels = {'trace', 'debug', 'info', 'warn'};
const _validIpv6Modes = {
  'ipv4_only',
  'prefer_ipv4',
  'prefer_ipv6',
  'ipv6_only',
};
const _validDomainStrategies = {
  '',
  'prefer_ipv6',
  'prefer_ipv4',
  'ipv4_only',
  'ipv6_only',
};
const _validTunImplementations = {'mixed', 'system', 'gvisor'};
const _validWarpDetourModes = {'proxyOverWarp', 'warpOverProxy'};

String _stringChoice(
  SharedPreferences p,
  String key,
  String fallback,
  Set<String> valid,
) {
  final value = p.getString(key);
  if (value == null || !valid.contains(value)) return fallback;
  return value;
}

/// [NetworkSettingsNotifier.importJson] 的结果。
///
/// 设计取舍：导入按"字段"为单位、逐个尝试——JSON 里没有的 key 直接跳过
/// （旧值原样保留，不算作"跳过"，因为压根不是这次导入的目标）；JSON 里有
/// 但类型不对（如把端口写成字符串）或没通过对应 setter 的校验（如端口越界）
/// 的 key 计入 [skippedKeys]，同样保留旧值，但会继续处理剩下的字段而不是
/// 整体失败——这样一份手改坏了一两个字段的 JSON 仍然能把其余字段正确导入，
/// 不必因为一个 typo 就全部作废（对齐参照项目 `importFromClipboard` 的
/// per-field try/catch 设计）。只有当整个输入连 JSON 都解析不了，或者顶层
/// 不是一个对象时才会整体失败，此时反映在 [parseError]，[appliedKeys] /
/// [skippedKeys] 均为空，NetworkSettings 状态完全不受影响。
class NetworkSettingsImportResult {
  const NetworkSettingsImportResult({
    required this.appliedKeys,
    required this.skippedKeys,
    this.parseError,
  });

  /// 成功写入 NetworkSettings 的字段（JSON key，驼峰命名，与导出格式一致）。
  final List<String> appliedKeys;

  /// JSON 里存在但类型不对 / 未通过校验，因而被跳过（旧值保留）的字段。
  final List<String> skippedKeys;

  /// 顶层 JSON 解析失败（非法 JSON 或不是对象）时的错误描述；成功解析则为
  /// null，即便 [appliedKeys] 为空。
  final String? parseError;

  bool get hasParseError => parseError != null;
}

final networkSettingsProvider =
    StateNotifierProvider<NetworkSettingsNotifier, NetworkSettings>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return NetworkSettingsNotifier(prefs);
    });

class NetworkSettingsNotifier extends StateNotifier<NetworkSettings> {
  NetworkSettingsNotifier(this.prefs) : super(_read(prefs));

  final SharedPreferences prefs;

  static NetworkSettings _read(SharedPreferences p) {
    return NetworkSettings(
      mixedPort: p.getInt(_kMixedPort) ?? 2080,
      region: _stringChoice(p, _kRegion, 'other', _validRegions),
      blockAds: p.getBool(_kBlockAds) ?? false,
      logLevel: _stringChoice(p, _kLogLevel, 'warn', _validLogLevels),
      bypassLan: p.getBool(_kBypassLan) ?? false,
      resolveDestination: p.getBool(_kResolveDestination) ?? false,
      ipv6Mode: _stringChoice(p, _kIpv6Mode, 'ipv4_only', _validIpv6Modes),
      setSystemProxy: p.getBool(_kSetSystemProxy) ?? true,
      enableTun: p.getBool(_kEnableTun) ?? false,
      allowConnectionFromLan: p.getBool(_kAllowLan) ?? false,
      enableDnsRouting: p.getBool(_kEnableDnsRouting) ?? true,
      enableFakeDns: p.getBool(_kEnableFakeDns) ?? false,
      independentDnsCache: p.getBool(_kIndependentDnsCache) ?? true,
      remoteDnsAddress:
          p.getString(_kRemoteDnsAddress) ?? 'https://1.1.1.1/dns-query',
      remoteDnsDomainStrategy: _stringChoice(
        p,
        _kRemoteDnsDomainStrategy,
        '',
        _validDomainStrategies,
      ),
      directDnsAddress: p.getString(_kDirectDnsAddress) ?? '1.1.1.1',
      directDnsDomainStrategy: _stringChoice(
        p,
        _kDirectDnsDomainStrategy,
        '',
        _validDomainStrategies,
      ),
      tunImplementation: _stringChoice(
        p,
        _kTunImplementation,
        'mixed',
        _validTunImplementations,
      ),
      strictRoute: p.getBool(_kStrictRoute) ?? true,
      mtu: p.getInt(_kMtu) ?? 9000,
      clashApiPort: p.getInt(_kClashApiPort) ?? 6756,
      tproxyPort: p.getInt(_kTproxyPort) ?? 2081,
      localDnsPort: p.getInt(_kLocalDnsPort) ?? 6450,
      enableTlsFragment: p.getBool(_kEnableTlsFragment) ?? false,
      tlsFragmentSize: p.getString(_kTlsFragmentSize) ?? '10-30',
      tlsFragmentSleep: p.getString(_kTlsFragmentSleep) ?? '50-200',
      enableTlsPadding: p.getBool(_kEnableTlsPadding) ?? false,
      enableTlsMixedSniCase: p.getBool(_kEnableTlsMixedSniCase) ?? false,
      tlsPaddingSize: p.getString(_kTlsPaddingSize) ?? '100-200',
      muxPadding: p.getBool(_kMuxPadding) ?? false,
      enableWarp: p.getBool(_kEnableWarp) ?? false,
      warpConsentGiven: p.getBool(_kWarpConsentGiven) ?? false,
      warpDetourMode: _stringChoice(
        p,
        _kWarpDetourMode,
        'proxyOverWarp',
        _validWarpDetourModes,
      ),
      warpLicenseKey: p.getString(_kWarpLicenseKey) ?? '',
      // fallback 与上面构造函数默认值保持一致：只有从未持久化过（key 不存在，
      // 即用户从没保存过）时才落到这些新默认值；已保存的用户偏好走 p.getX(...) 的
      // 非 null 分支，不受这次改动影响。
      warpCleanIp: p.getString(_kWarpCleanIp) ?? 'auto',
      warpPort: p.getInt(_kWarpPort) ?? 0,
      warpNoise: p.getString(_kWarpNoise) ?? '1-3',
      warpNoiseSize: p.getString(_kWarpNoiseSize) ?? '10-30',
      warpNoiseMode: p.getString(_kWarpNoiseMode) ?? 'm6',
      warpNoiseDelay: p.getString(_kWarpNoiseDelay) ?? '10-30',
      warpAccountId: p.getString(_kWarpAccountId) ?? '',
      warpAccessToken: p.getString(_kWarpAccessToken) ?? '',
      warpWireguardConfig: p.getString(_kWarpWireguardConfig) ?? '',
      connectionTestUrl:
          p.getString(_kConnectionTestUrl) ??
          'http://connectivitycheck.gstatic.com/generate_204',
      urlTestIntervalSeconds: p.getInt(_kUrlTestIntervalSeconds) ?? 600,
    );
  }

  Future<void> setMixedPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('port out of range: $port');
    }
    state = state.copyWith(mixedPort: port);
    await prefs.setInt(_kMixedPort, port);
  }

  Future<void> setRegion(String value) async {
    if (!_validRegions.contains(value)) {
      throw ArgumentError('invalid region: $value');
    }
    state = state.copyWith(region: value);
    await prefs.setString(_kRegion, value);
  }

  Future<void> setBlockAds(bool value) async {
    state = state.copyWith(blockAds: value);
    await prefs.setBool(_kBlockAds, value);
  }

  Future<void> setLogLevel(String value) async {
    if (!_validLogLevels.contains(value)) {
      throw ArgumentError('invalid log level: $value');
    }
    state = state.copyWith(logLevel: value);
    await prefs.setString(_kLogLevel, value);
  }

  Future<void> setBypassLan(bool value) async {
    state = state.copyWith(bypassLan: value);
    await prefs.setBool(_kBypassLan, value);
  }

  Future<void> setResolveDestination(bool value) async {
    state = state.copyWith(resolveDestination: value);
    await prefs.setBool(_kResolveDestination, value);
  }

  Future<void> setIpv6Mode(String value) async {
    if (!_validIpv6Modes.contains(value)) {
      throw ArgumentError('invalid ipv6 mode: $value');
    }
    state = state.copyWith(ipv6Mode: value);
    await prefs.setString(_kIpv6Mode, value);
  }

  Future<void> setSystemProxy(bool value) async {
    state = state.copyWith(setSystemProxy: value);
    await prefs.setBool(_kSetSystemProxy, value);
  }

  Future<void> setEnableTun(bool value) async {
    state = state.copyWith(enableTun: value);
    await prefs.setBool(_kEnableTun, value);
  }

  Future<void> setAllowLan(bool value) async {
    state = state.copyWith(allowConnectionFromLan: value);
    await prefs.setBool(_kAllowLan, value);
  }

  Future<void> setEnableDnsRouting(bool value) async {
    state = state.copyWith(enableDnsRouting: value);
    await prefs.setBool(_kEnableDnsRouting, value);
  }

  Future<void> setEnableFakeDns(bool value) async {
    state = state.copyWith(enableFakeDns: value);
    await prefs.setBool(_kEnableFakeDns, value);
  }

  Future<void> setIndependentDnsCache(bool value) async {
    state = state.copyWith(independentDnsCache: value);
    await prefs.setBool(_kIndependentDnsCache, value);
  }

  Future<void> setRemoteDnsAddress(String address) async {
    state = state.copyWith(remoteDnsAddress: address);
    await prefs.setString(_kRemoteDnsAddress, address);
  }

  Future<void> setRemoteDnsDomainStrategy(String value) async {
    if (!_validDomainStrategies.contains(value)) {
      throw ArgumentError('invalid remote DNS domain strategy: $value');
    }
    state = state.copyWith(remoteDnsDomainStrategy: value);
    await prefs.setString(_kRemoteDnsDomainStrategy, value);
  }

  Future<void> setDirectDnsAddress(String address) async {
    state = state.copyWith(directDnsAddress: address);
    await prefs.setString(_kDirectDnsAddress, address);
  }

  Future<void> setDirectDnsDomainStrategy(String value) async {
    if (!_validDomainStrategies.contains(value)) {
      throw ArgumentError('invalid direct DNS domain strategy: $value');
    }
    state = state.copyWith(directDnsDomainStrategy: value);
    await prefs.setString(_kDirectDnsDomainStrategy, value);
  }

  Future<void> setTunImplementation(String value) async {
    if (!_validTunImplementations.contains(value)) {
      throw ArgumentError('invalid TUN implementation: $value');
    }
    state = state.copyWith(tunImplementation: value);
    await prefs.setString(_kTunImplementation, value);
  }

  Future<void> setStrictRoute(bool value) async {
    state = state.copyWith(strictRoute: value);
    await prefs.setBool(_kStrictRoute, value);
  }

  Future<void> setMtu(int value) async {
    if (value <= 0) {
      throw ArgumentError('invalid mtu: $value');
    }
    state = state.copyWith(mtu: value);
    await prefs.setInt(_kMtu, value);
  }

  Future<void> setClashApiPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('clash api port out of range: $port');
    }
    state = state.copyWith(clashApiPort: port);
    await prefs.setInt(_kClashApiPort, port);
  }

  Future<void> setTproxyPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('tproxy port out of range: $port');
    }
    state = state.copyWith(tproxyPort: port);
    await prefs.setInt(_kTproxyPort, port);
  }

  Future<void> setLocalDnsPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('local dns port out of range: $port');
    }
    state = state.copyWith(localDnsPort: port);
    await prefs.setInt(_kLocalDnsPort, port);
  }

  Future<void> setEnableTlsFragment(bool value) async {
    state = state.copyWith(enableTlsFragment: value);
    await prefs.setBool(_kEnableTlsFragment, value);
  }

  Future<void> setTlsFragmentSize(String value) async {
    final range = value.trim();
    if (range.isEmpty) {
      throw ArgumentError('TLS fragment size cannot be empty');
    }
    state = state.copyWith(tlsFragmentSize: range);
    await prefs.setString(_kTlsFragmentSize, range);
  }

  Future<void> setTlsFragmentSleep(String value) async {
    final range = value.trim();
    if (range.isEmpty) {
      throw ArgumentError('TLS fragment sleep cannot be empty');
    }
    state = state.copyWith(tlsFragmentSleep: range);
    await prefs.setString(_kTlsFragmentSleep, range);
  }

  Future<void> setEnableTlsPadding(bool value) async {
    state = state.copyWith(enableTlsPadding: value);
    await prefs.setBool(_kEnableTlsPadding, value);
  }

  Future<void> setEnableTlsMixedSniCase(bool value) async {
    state = state.copyWith(enableTlsMixedSniCase: value);
    await prefs.setBool(_kEnableTlsMixedSniCase, value);
  }

  Future<void> setTlsPaddingSize(String value) async {
    final range = value.trim();
    if (range.isEmpty) {
      throw ArgumentError('TLS padding size cannot be empty');
    }
    state = state.copyWith(tlsPaddingSize: range);
    await prefs.setString(_kTlsPaddingSize, range);
  }

  Future<void> setMuxPadding(bool value) async {
    state = state.copyWith(muxPadding: value);
    await prefs.setBool(_kMuxPadding, value);
  }

  Future<void> setEnableWarp(bool value) async {
    state = state.copyWith(enableWarp: value);
    await prefs.setBool(_kEnableWarp, value);
  }

  Future<void> setWarpConsentGiven(bool value) async {
    state = state.copyWith(warpConsentGiven: value);
    await prefs.setBool(_kWarpConsentGiven, value);
  }

  Future<void> setWarpDetourMode(String value) async {
    if (!_validWarpDetourModes.contains(value)) {
      throw ArgumentError('invalid WARP detour mode: $value');
    }
    state = state.copyWith(warpDetourMode: value);
    await prefs.setString(_kWarpDetourMode, value);
  }

  Future<void> setWarpLicenseKey(String value) async {
    state = state.copyWith(warpLicenseKey: value.trim());
    await prefs.setString(_kWarpLicenseKey, value.trim());
  }

  Future<void> setWarpCleanIp(String value) async {
    state = state.copyWith(warpCleanIp: value.trim());
    await prefs.setString(_kWarpCleanIp, value.trim());
  }

  Future<void> setWarpPort(int port) async {
    if (port < 1024 || port > 65535) {
      throw ArgumentError('WARP port out of range: $port');
    }
    state = state.copyWith(warpPort: port);
    await prefs.setInt(_kWarpPort, port);
  }

  Future<void> setWarpNoise(String value) async {
    state = state.copyWith(warpNoise: value.trim());
    await prefs.setString(_kWarpNoise, value.trim());
  }

  Future<void> setWarpNoiseSize(String value) async {
    state = state.copyWith(warpNoiseSize: value.trim());
    await prefs.setString(_kWarpNoiseSize, value.trim());
  }

  Future<void> setWarpNoiseMode(String value) async {
    state = state.copyWith(warpNoiseMode: value.trim());
    await prefs.setString(_kWarpNoiseMode, value.trim());
  }

  Future<void> setWarpNoiseDelay(String value) async {
    state = state.copyWith(warpNoiseDelay: value.trim());
    await prefs.setString(_kWarpNoiseDelay, value.trim());
  }

  /// [value] 来自 `generateWarpConfig` 的 native 响应，不是用户手输，
  /// 故意不 trim —— 原样保存，避免意外改动 native 给的凭证。
  Future<void> setWarpAccountId(String value) async {
    state = state.copyWith(warpAccountId: value);
    await prefs.setString(_kWarpAccountId, value);
  }

  Future<void> setWarpAccessToken(String value) async {
    state = state.copyWith(warpAccessToken: value);
    await prefs.setString(_kWarpAccessToken, value);
  }

  Future<void> setWarpWireguardConfig(String value) async {
    state = state.copyWith(warpWireguardConfig: value);
    await prefs.setString(_kWarpWireguardConfig, value);
  }

  Future<void> setConnectionTestUrl(String url) async {
    state = state.copyWith(connectionTestUrl: url);
    await prefs.setString(_kConnectionTestUrl, url);
  }

  Future<void> setUrlTestIntervalSeconds(int seconds) async {
    if (seconds < 60 || seconds > 3600) {
      throw ArgumentError('url test interval out of range: $seconds');
    }
    state = state.copyWith(urlTestIntervalSeconds: seconds);
    await prefs.setInt(_kUrlTestIntervalSeconds, seconds);
  }

  /// 解析 [raw]（"配置选项 JSON"，与 `_networkSettingsJson` 导出的格式一致），
  /// 把其中能识别的字段写回 NetworkSettings + SharedPreferences。
  ///
  /// 逐字段处理，见 [NetworkSettingsImportResult] 的设计说明。
  Future<NetworkSettingsImportResult> importJson(String raw) async {
    final Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const NetworkSettingsImportResult(
          appliedKeys: [],
          skippedKeys: [],
          parseError: 'JSON 顶层必须是一个对象',
        );
      }
      map = Map<String, dynamic>.from(decoded);
    } on FormatException catch (e) {
      return NetworkSettingsImportResult(
        appliedKeys: const [],
        skippedKeys: const [],
        parseError: 'JSON 解析失败: ${e.message}',
      );
    }

    final applied = <String>[];
    final skipped = <String>[];

    Future<void> apply(
      String key,
      Future<void> Function(dynamic rawValue) setter,
    ) async {
      if (!map.containsKey(key)) return;
      try {
        await setter(map[key]);
        applied.add(key);
      } catch (_) {
        skipped.add(key);
      }
    }

    Future<void> applyInt(String key, Future<void> Function(int) setter) =>
        apply(key, (v) async {
          final int parsed;
          if (v is int) {
            parsed = v;
          } else if (v is num) {
            parsed = v.toInt();
          } else {
            throw ArgumentError('$key must be a number');
          }
          await setter(parsed);
        });

    Future<void> applyBool(String key, Future<void> Function(bool) setter) =>
        apply(key, (v) async {
          if (v is! bool) throw ArgumentError('$key must be a bool');
          await setter(v);
        });

    Future<void> applyString(
      String key,
      Future<void> Function(String) setter,
    ) => apply(key, (v) async {
      if (v is! String) throw ArgumentError('$key must be a string');
      await setter(v);
    });

    await applyInt('mixedPort', setMixedPort);
    await applyString('region', setRegion);
    await applyBool('blockAds', setBlockAds);
    await applyString('logLevel', setLogLevel);
    await applyBool('bypassLan', setBypassLan);
    await applyBool('resolveDestination', setResolveDestination);
    await applyString('ipv6Mode', setIpv6Mode);
    await applyBool('setSystemProxy', setSystemProxy);
    await applyBool('enableTun', setEnableTun);
    await applyBool('allowConnectionFromLan', setAllowLan);
    await applyBool('enableDnsRouting', setEnableDnsRouting);
    await applyString('remoteDnsAddress', setRemoteDnsAddress);
    await applyString('remoteDnsDomainStrategy', setRemoteDnsDomainStrategy);
    await applyString('directDnsAddress', setDirectDnsAddress);
    await applyString('directDnsDomainStrategy', setDirectDnsDomainStrategy);
    await applyString('tunImplementation', setTunImplementation);
    await applyBool('strictRoute', setStrictRoute);
    await applyBool('enableTlsFragment', setEnableTlsFragment);
    await applyString('tlsFragmentSize', setTlsFragmentSize);
    await applyBool('enableTlsPadding', setEnableTlsPadding);
    await applyString('connectionTestUrl', setConnectionTestUrl);
    await applyInt('urlTestIntervalSeconds', setUrlTestIntervalSeconds);

    // 高级配置字段（此前只能硬编码，现在跟其余字段走同一条导入通道）。
    await applyBool('enableFakeDns', setEnableFakeDns);
    await applyBool('independentDnsCache', setIndependentDnsCache);
    await applyInt('mtu', setMtu);
    await applyInt('clashApiPort', setClashApiPort);
    await applyInt('tproxyPort', setTproxyPort);
    await applyInt('localDnsPort', setLocalDnsPort);
    await applyString('tlsFragmentSleep', setTlsFragmentSleep);
    await applyBool('enableTlsMixedSniCase', setEnableTlsMixedSniCase);
    await applyString('tlsPaddingSize', setTlsPaddingSize);
    await applyBool('muxPadding', setMuxPadding);

    // WARP 用户可调设置——跟其余字段走同一条导入通道，否则备份/迁移会丢失
    // WARP 配置。故意不含 warpAccountId/warpAccessToken/warpWireguardConfig：
    // 这 3 个是 generateWarpConfig 生成写入的运行时凭证，不是用户设置，见
    // _networkSettingsJson 的同款说明。
    await applyBool('enableWarp', setEnableWarp);
    await applyBool('warpConsentGiven', setWarpConsentGiven);
    await applyString('warpDetourMode', setWarpDetourMode);
    await applyString('warpLicenseKey', setWarpLicenseKey);
    await applyString('warpCleanIp', setWarpCleanIp);
    await applyInt('warpPort', setWarpPort);
    await applyString('warpNoise', setWarpNoise);
    await applyString('warpNoiseSize', setWarpNoiseSize);
    await applyString('warpNoiseMode', setWarpNoiseMode);
    await applyString('warpNoiseDelay', setWarpNoiseDelay);

    return NetworkSettingsImportResult(
      appliedKeys: applied,
      skippedKeys: skipped,
    );
  }

  Future<void> reset() async {
    state = const NetworkSettings();
    await Future.wait([
      prefs.remove(_kMixedPort),
      prefs.remove(_kRegion),
      prefs.remove(_kBlockAds),
      prefs.remove(_kLogLevel),
      prefs.remove(_kBypassLan),
      prefs.remove(_kResolveDestination),
      prefs.remove(_kIpv6Mode),
      prefs.remove(_kSetSystemProxy),
      prefs.remove(_kEnableTun),
      prefs.remove(_kAllowLan),
      prefs.remove(_kEnableDnsRouting),
      prefs.remove(_kEnableFakeDns),
      prefs.remove(_kIndependentDnsCache),
      prefs.remove(_kRemoteDnsAddress),
      prefs.remove(_kRemoteDnsDomainStrategy),
      prefs.remove(_kDirectDnsAddress),
      prefs.remove(_kDirectDnsDomainStrategy),
      prefs.remove(_kTunImplementation),
      prefs.remove(_kStrictRoute),
      prefs.remove(_kMtu),
      prefs.remove(_kClashApiPort),
      prefs.remove(_kTproxyPort),
      prefs.remove(_kLocalDnsPort),
      prefs.remove(_kEnableTlsFragment),
      prefs.remove(_kTlsFragmentSize),
      prefs.remove(_kTlsFragmentSleep),
      prefs.remove(_kEnableTlsPadding),
      prefs.remove(_kEnableTlsMixedSniCase),
      prefs.remove(_kTlsPaddingSize),
      prefs.remove(_kMuxPadding),
      prefs.remove(_kEnableWarp),
      prefs.remove(_kWarpConsentGiven),
      prefs.remove(_kWarpDetourMode),
      prefs.remove(_kWarpLicenseKey),
      prefs.remove(_kWarpCleanIp),
      prefs.remove(_kWarpPort),
      prefs.remove(_kWarpNoise),
      prefs.remove(_kWarpNoiseSize),
      prefs.remove(_kWarpNoiseMode),
      prefs.remove(_kWarpNoiseDelay),
      prefs.remove(_kWarpAccountId),
      prefs.remove(_kWarpAccessToken),
      prefs.remove(_kWarpWireguardConfig),
      prefs.remove(_kConnectionTestUrl),
      prefs.remove(_kUrlTestIntervalSeconds),
    ]);
  }
}
