import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/config/data/default_config_options.dart';
import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/golden_file.dart';

/// 跨语言契约：Dart 的 `getDefaultConfigOptions` 对一组设置矩阵的输出，入库成
/// `kernel/testdata/options/*.json`，Go 的选项解码（`dart_fixture_test.go`）把全部
/// 夹具读一遍——Dart 产生任何 Go 不认识的键就失败。反向：Go 已知的键集合与
/// `keys.txt` 的非 go-only 部分一致。
///
/// 产出口径是 Android：`debugServiceModePlatformOverride` 把宿主机伪装成 Android，
/// 否则 `set-system-proxy` / `enable-tun` 会按桌面口径算。
const _dir = 'kernel/testdata/options';

/// Go 独有的键：Dart 不产生，也没有界面入口；这一节在 keys.txt 里单独标出，
/// 不触发「Dart 键漂移」检查。
const _goOnlyKeys = [
  'bootstrap-dns-address',
  'web-secret',
  // 规则项里 Dart 只写 ip / domains / outbound；其余是 Go 规则模型支持、Dart 暂未产生的条件。
  'rules[].network',
  'rules[].port',
  'rules[].protocol',
];

const _synthWarpConfig =
    '{"private-key":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",'
    '"local-address-ipv4":"172.16.0.2","local-address-ipv6":"2001:db8::2",'
    '"peer-public-key":"ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=",'
    '"client-id":"AQID"}';

class _Case {
  const _Case(this.name, this.settings, {this.isSmart = false, this.advanced});

  final String name;
  final NetworkSettings settings;
  final bool isSmart;
  final AdvancedConfig? advanced;
}

/// 本地形态的默认设置。`NetworkSettings` 的默认 `setSystemProxy` 是 true，
/// 在 Android 上落在「VPN」档（默认形态）；仅线路要两个开关都关。
const _base = NetworkSettings();

final _cases = <_Case>[
  const _Case('default', _base),
  const _Case('vpn-smart', _base, isSmart: true),
  _Case(
    'line-only-global',
    _base.copyWith(enableTun: false, setSystemProxy: false),
  ),
  _Case(
    'fakedns-dnsrouting-bypasslan',
    _base.copyWith(
      enableFakeDns: true,
      enableDnsRouting: true,
      bypassLan: true,
    ),
  ),
  _Case(
    'mux-fragment',
    _base.copyWith(enableTlsFragment: true, muxPadding: true),
    advanced: const AdvancedConfig(
      muxEnabled: true,
      muxProtocol: 'h2mux',
      muxConcurrency: 8,
      fragmentEnabled: true,
      fragmentRange: '20-50',
    ),
  ),
  _Case(
    'warp-proxy-over-warp',
    _base.copyWith(
      enableWarp: true,
      warpDetourMode: 'proxyOverWarp',
      warpWireguardConfig: _synthWarpConfig,
      warpLicenseKey: 'synthetic-license-key',
    ),
  ),
  _Case(
    'warp-warp-over-proxy',
    _base.copyWith(
      enableWarp: true,
      warpDetourMode: 'warpOverProxy',
      warpWireguardConfig: _synthWarpConfig,
      warpCleanIp: '162.159.192.7',
      warpPort: 2408,
    ),
  ),
  // 远程与直连 DNS 各地址形态。
  _Case(
    'dns-ip',
    _base.copyWith(remoteDnsAddress: '1.1.1.1', directDnsAddress: '223.5.5.5'),
  ),
  _Case(
    'dns-https-domain',
    _base.copyWith(remoteDnsAddress: 'https://doh.example.net/dns-query'),
  ),
  _Case(
    'dns-https-ip',
    _base.copyWith(remoteDnsAddress: 'https://1.1.1.1/dns-query'),
  ),
  _Case(
    'dns-h3',
    _base.copyWith(remoteDnsAddress: 'h3://doh.example.net/dns-query'),
  ),
  _Case('dns-tls', _base.copyWith(remoteDnsAddress: 'tls://dot.example.net')),
  _Case('dns-quic', _base.copyWith(remoteDnsAddress: 'quic://doq.example.net')),
  _Case('dns-tcp', _base.copyWith(remoteDnsAddress: 'tcp://1.1.1.1')),
  _Case('dns-udp', _base.copyWith(remoteDnsAddress: 'udp://1.1.1.1')),
  _Case('dns-local', _base.copyWith(remoteDnsAddress: 'local')),
  _Case(
    'dns-direct-doh-domain',
    _base.copyWith(directDnsAddress: 'https://doh.example.net/dns-query'),
  ),
  _Case(
    'dns-strategies',
    _base.copyWith(
      remoteDnsDomainStrategy: 'prefer_ipv4',
      directDnsDomainStrategy: 'ipv4_only',
    ),
  ),
  // 高级配置里的订阅级远程 DNS 覆盖优先于全局设置。
  _Case(
    'dns-remote-override',
    _base.copyWith(remoteDnsAddress: 'https://1.1.1.1/dns-query'),
    advanced: const AdvancedConfig(remoteDnsOverride: 'tls://dot.example.net'),
  ),
  // IPv6 各模式。
  _Case('ipv6-ipv4-only', _base.copyWith(ipv6Mode: 'ipv4_only')),
  _Case('ipv6-prefer-ipv4', _base.copyWith(ipv6Mode: 'prefer_ipv4')),
  _Case('ipv6-prefer-ipv6', _base.copyWith(ipv6Mode: 'prefer_ipv6')),
  _Case('ipv6-only', _base.copyWith(ipv6Mode: 'ipv6_only')),
  _Case('allow-lan', _base.copyWith(allowConnectionFromLan: true)),
  _Case('resolve-destination', _base.copyWith(resolveDestination: true)),
  // 界面已隐藏、但存档里仍可能带着的值：键与值照常产出，内核按警告处理，不丢。
  _Case(
    'persisted-hidden-options',
    _base.copyWith(
      blockAds: true,
      enableTlsPadding: true,
      enableTlsMixedSniCase: true,
      tlsFragmentSize: '5-9',
      tlsFragmentSleep: '1-2',
      tlsPaddingSize: '10-20',
      warpNoise: '2-4',
      warpNoiseSize: '11-31',
      warpNoiseDelay: '11-31',
      warpNoiseMode: 'm5',
    ),
  ),
  _Case(
    'ports-and-tun',
    _base.copyWith(
      mixedPort: 7890,
      tproxyPort: 7891,
      localDnsPort: 7853,
      mtu: 1500,
      strictRoute: false,
      tunImplementation: 'gvisor',
      logLevel: 'debug',
      urlTestIntervalSeconds: 300,
      connectionTestUrl: 'https://www.gstatic.com/generate_204',
    ),
  ),
];

Map<String, dynamic> _sub(Map<String, dynamic> m, String key) =>
    m[key] as Map<String, dynamic>;

String _encode(Map<String, dynamic> options) =>
    '${const JsonEncoder.withIndent('  ').convert(options)}\n';

/// 一份选项里全部键的路径：顶层键、嵌套对象的 `父.子`、规则项的 `rules[].键`。
Set<String> _keyPaths(Map<String, dynamic> options) {
  final out = <String>{};
  void walk(String prefix, Object? value) {
    if (value is Map) {
      for (final e in value.entries) {
        final path = prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}';
        out.add(path);
        walk(path, e.value);
      }
    } else if (value is List) {
      for (final item in value) {
        if (item is Map) {
          for (final e in item.entries) {
            final path = '$prefix[].${e.key}';
            out.add(path);
            walk(path, e.value);
          }
        }
      }
    }
  }

  walk('', options);
  return out;
}

const _keysHeader =
    '# Dart 的 getDefaultConfigOptions 产生的全部选项键（顶层键、父.子、rules[].键）。\n'
    '# 由 options_fixture_export_test.dart 生成（UPDATE_GOLDEN=1），不要手改。\n'
    '# go-only 一节是只有 Go 侧认识的键（来自该测试里的 _goOnlyKeys 常量）；Go 的\n'
    '# dart_fixture_test.go 校验「dart ∪ go-only == Go 已知键」且两节不相交。\n';

String _keysFile(Set<String> dartKeys) {
  final sorted = dartKeys.toList()..sort();
  final goOnly = [..._goOnlyKeys]..sort();
  return '$_keysHeader[dart]\n${sorted.join('\n')}\n[go-only]\n${goOnly.join('\n')}\n';
}

void main() {
  setUp(() => debugServiceModePlatformOverride = ServiceModePlatform.android);
  tearDown(() => debugServiceModePlatformOverride = null);

  Map<String, dynamic> optionsOf(_Case c) => getDefaultConfigOptions(
    isSmart: c.isSmart,
    settings: c.settings,
    advancedConfig: c.advanced,
  );

  test('夹具名唯一', () {
    final names = _cases.map((c) => c.name).toList();
    expect(names.toSet().length, names.length);
  });

  for (final c in _cases) {
    test('${c.name}.json 与 getDefaultConfigOptions 的输出逐字节一致', () {
      expectGoldenFile('$_dir/${c.name}.json', _encode(optionsOf(c)));
    });
  }

  test('keys.txt：dart 一节 = 全部夹具里出现过的键，go-only 一节原样', () {
    final dartKeys = <String>{};
    for (final c in _cases) {
      dartKeys.addAll(_keyPaths(optionsOf(c)));
    }
    expect(
      dartKeys.intersection(_goOnlyKeys.toSet()),
      isEmpty,
      reason: 'go-only 的键 Dart 不该产生',
    );
    expectGoldenFile('$_dir/keys.txt', _keysFile(dartKeys));
  });

  test('夹具目录里没有矩阵之外的文件', () {
    if (updateGolden) {
      // 重写时顺带清掉矩阵里已不存在的夹具，避免旧文件悄悄留在评审之外。
      final want = {for (final c in _cases) '${c.name}.json', 'keys.txt'};
      for (final f in Directory(_dir).listSync().whereType<File>()) {
        if (!want.contains(f.uri.pathSegments.last)) f.deleteSync();
      }
    }
    final names = {
      for (final f in Directory(_dir).listSync().whereType<File>())
        f.uri.pathSegments.last,
    };
    expect(names, {for (final c in _cases) '${c.name}.json', 'keys.txt'});
  });

  test('矩阵覆盖该覆盖的形态（防止夹具被悄悄删成空壳）', () {
    final byName = {for (final c in _cases) c.name: optionsOf(c)};
    expect(byName['default']!['enable-tun'], isTrue);
    expect(byName['default']!['set-system-proxy'], isFalse, reason: 'Android');
    expect(byName['default']!['rules'], isEmpty);
    expect((byName['vpn-smart']!['rules'] as List), hasLength(2));
    expect(byName['line-only-global']!['enable-tun'], isFalse);
    expect(
      _sub(byName['warp-proxy-over-warp']!, 'warp')['mode'],
      'proxy_over_warp',
    );
    expect(
      _sub(byName['warp-warp-over-proxy']!, 'warp')['mode'],
      'warp_over_proxy',
    );
    expect(
      byName['dns-remote-override']!['remote-dns-address'],
      'tls://dot.example.net',
    );
    expect(
      _sub(byName['mux-fragment']!, 'tls-tricks')['enable-fragment'],
      isTrue,
    );
    expect(
      _sub(byName['mux-fragment']!, 'tls-tricks')['fragment-size'],
      '20-50',
    );
    for (final mode in [
      'ipv4_only',
      'prefer_ipv4',
      'prefer_ipv6',
      'ipv6_only',
    ]) {
      expect(
        byName.values.any((o) => o['ipv6-mode'] == mode),
        isTrue,
        reason: mode,
      );
    }
  });
}
