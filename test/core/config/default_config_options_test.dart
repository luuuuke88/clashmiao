import 'package:clashmiao/core/config/cn_direct_rules.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getDefaultConfigOptions warp 字段映射', () {
    test('默认 NetworkSettings 下 warp 块保持关闭 + 对齐推荐默认值', () {
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(),
      );
      final warp = options['warp'] as Map<String, dynamic>;

      expect(warp['enable'], isFalse);
      expect(warp['mode'], 'proxy_over_warp');
      expect(warp['wireguard-config'], '');
      expect(warp['license-key'], '');
      expect(warp['account-id'], '');
      expect(warp['access-token'], '');
      // 以下 6 项对齐参照项目推荐默认值，而非全空/固定端口。
      expect(warp['clean-ip'], 'auto');
      expect(warp['clean-port'], 0); // NetworkSettings.warpPort 默认值
      expect(warp['noise'], '1-3');
      expect(warp['noise-size'], '10-30');
      expect(warp['noise-delay'], '10-30');
      expect(warp['noise-mode'], 'm6');
    });

    test('自定义 WARP 设置真正透传进 warp 块（不再是硬编码空串）', () {
      const settings = NetworkSettings(
        enableWarp: true,
        warpDetourMode: 'proxyOverWarp',
        warpLicenseKey: 'license-xyz',
        warpCleanIp: '162.159.192.1',
        warpPort: 2408,
        warpNoise: '10-20',
        warpNoiseSize: '5-15',
        warpNoiseMode: 'm4',
        warpNoiseDelay: '1-2',
        warpAccountId: 'account-abc',
        warpAccessToken: 'token-abc',
        warpWireguardConfig: '{"private_key":"pk"}',
      );

      final options = getDefaultConfigOptions(settings: settings);
      final warp = options['warp'] as Map<String, dynamic>;

      expect(warp['enable'], isTrue);
      expect(warp['mode'], 'proxy_over_warp');
      expect(warp['wireguard-config'], '{"private_key":"pk"}');
      expect(warp['license-key'], 'license-xyz');
      expect(warp['account-id'], 'account-abc');
      expect(warp['access-token'], 'token-abc');
      expect(warp['clean-ip'], '162.159.192.1');
      expect(warp['clean-port'], 2408);
      expect(warp['noise'], '10-20');
      expect(warp['noise-size'], '5-15');
      expect(warp['noise-delay'], '1-2');
      expect(warp['noise-mode'], 'm4');
    });

    test('warpDetourMode=warpOverProxy 映射成 mode=warp_over_proxy', () {
      const settings = NetworkSettings(warpDetourMode: 'warpOverProxy');

      final options = getDefaultConfigOptions(settings: settings);
      final warp = options['warp'] as Map<String, dynamic>;

      expect(warp['mode'], 'warp_over_proxy');
    });

    test('warp2 块保持原状（未接入设置，仍然是关闭 + 空值占位）', () {
      const settings = NetworkSettings(
        enableWarp: true,
        warpLicenseKey: 'license-xyz',
        warpAccountId: 'account-abc',
      );

      final options = getDefaultConfigOptions(settings: settings);
      final warp2 = options['warp2'] as Map<String, dynamic>;

      expect(warp2['enable'], isFalse);
      expect(warp2['license-key'], '');
      expect(warp2['account-id'], '');
      expect(warp2['access-token'], '');
      expect(warp2['wireguard-config'], '');
    });

    test('settings 为 null 时退回默认 NetworkSettings，warp 块不崩溃', () {
      final options = getDefaultConfigOptions();
      final warp = options['warp'] as Map<String, dynamic>;

      expect(warp['enable'], isFalse);
      expect(warp['mode'], 'proxy_over_warp');
    });
  });

  // ===========================================================
  // wave3: 高级配置字段不再是硬编码常量，而是来自 NetworkSettings —— 这是
  // "数据模型接入 config 生成"这条链路的关键验证：默认 NetworkSettings 下
  // 生成的值要跟此前的硬编码常量完全一致（不引入行为回归），而改一下
  // NetworkSettings 里的值，生成的配置 JSON 必须跟着变（证明真的读的是
  // settings 而不是常量）。
  // ===========================================================
  group('getDefaultConfigOptions 高级字段来自 NetworkSettings（不再硬编码）', () {
    test('默认 NetworkSettings 下，高级字段的值等于此前的硬编码常量', () {
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(),
      );
      final tlsTricks = options['tls-tricks'] as Map<String, dynamic>;
      final mux = options['mux'] as Map<String, dynamic>;

      expect(options['mtu'], 9000);
      expect(options['clash-api-port'], 6756);
      expect(options['tproxy-port'], 2081);
      expect(options['local-dns-port'], 6450);
      expect(options['enable-fake-dns'], isFalse);
      expect(options['independent-dns-cache'], isTrue);
      expect(tlsTricks['fragment-sleep'], '50-200');
      expect(tlsTricks['mixed-sni-case'], isFalse);
      expect(tlsTricks['padding-size'], '100-200');
      expect(mux['padding'], isFalse);
    });

    test('自定义 NetworkSettings 的高级字段真正透传进生成的配置（不再是硬编码常量）', () {
      const settings = NetworkSettings(
        mtu: 1400,
        clashApiPort: 19001,
        tproxyPort: 19002,
        localDnsPort: 19003,
        enableFakeDns: true,
        independentDnsCache: false,
        tlsFragmentSleep: '2-8',
        enableTlsMixedSniCase: true,
        tlsPaddingSize: '1-1500',
        muxPadding: true,
      );

      final options = getDefaultConfigOptions(settings: settings);
      final tlsTricks = options['tls-tricks'] as Map<String, dynamic>;
      final mux = options['mux'] as Map<String, dynamic>;

      expect(options['mtu'], 1400);
      expect(options['clash-api-port'], 19001);
      expect(options['tproxy-port'], 19002);
      expect(options['local-dns-port'], 19003);
      expect(options['enable-fake-dns'], isTrue);
      expect(options['independent-dns-cache'], isFalse);
      expect(tlsTricks['fragment-sleep'], '2-8');
      expect(tlsTricks['mixed-sni-case'], isTrue);
      expect(tlsTricks['padding-size'], '1-1500');
      expect(mux['padding'], isTrue);
    });
  });

  // ===========================================================
  // 智能分流真正生效的信号搬到了这里：这个 sing-box fork 的
  // config.BuildConfig()（libcore/config/config.go）无条件丢弃/重建 profile
  // 自带的 route 块，RuntimeConfigBuilder 原来写进 runtime-config.json 的
  // route.rules 从未真正生效过。这个 fork 真正认的自定义路由口子是
  // configOptions.rules（对应 libcore/config/rules.go 的 Rule.MakeRule()），
  // 所以智能分流数据必须通过这里注入，而不是 runtime-config.json 的 route 块。
  // ===========================================================
  group('getDefaultConfigOptions isSmart 驱动 rules（真正生效的智能分流口子）', () {
    test('isSmart=true 时，rules 里包含中国 IP 段直连规则', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      final rules = (options['rules'] as List).cast<Map<String, dynamic>>();

      final ipRule = rules.firstWhere(
        (r) => r['ip'] != null,
        orElse: () => <String, dynamic>{},
      );
      expect(ipRule, isNotEmpty, reason: 'isSmart=true 必须有一条基于 IP 的直连规则');
      expect(ipRule['outbound'], 'bypass');
      final ipList = (ipRule['ip'] as String).split(',');
      expect(
        ipList.length,
        cnDirectCidrRanges.length,
        reason: 'IP 规则必须包含反编译自 geoip-cn.srs 的完整 CIDR 列表',
      );
      expect(ipList, contains('1.0.1.0/24'));
    });

    test('isSmart=true 时，rules 里包含中国主流域名直连规则', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      final rules = (options['rules'] as List).cast<Map<String, dynamic>>();

      final domainRule = rules.firstWhere(
        (r) => r['domains'] != null,
        orElse: () => <String, dynamic>{},
      );
      expect(domainRule, isNotEmpty, reason: 'isSmart=true 必须有一条基于域名的直连规则');
      expect(domainRule['outbound'], 'bypass');
      final domains = (domainRule['domains'] as String).split(',');
      expect(
        domains,
        containsAll(['domain:cn', 'domain:baidu.com', 'domain:qq.com']),
      );
    });

    test('isSmart=false（全局模式）时，rules 为空——不做任何直连兜底', () {
      final options = getDefaultConfigOptions(
        isSmart: false,
        settings: const NetworkSettings(),
      );
      expect(options['rules'], isEmpty);
    });

    test('不传 isSmart 时默认等同 false（不破坏现有调用点）', () {
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(),
      );
      expect(options['rules'], isEmpty);
    });

    // 这个 sing-box fork 的 DNS 规则应用整段被 `if opt.EnableDNSRouting` 包住
    // （libcore/config/config.go），isSmart=true 时上面那两条直连规则要真正
    // 生效，enable-dns-routing 必须为 true——即使用户在设置页把"DNS 路由"
    // 这个开关关掉了，也不能连带把智能分流的直连规则一起废掉。
    test('isSmart=true 时 enable-dns-routing 强制为 true，不受用户设置开关影响', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(enableDnsRouting: false),
      );
      expect(options['enable-dns-routing'], isTrue);
    });

    test('isSmart=false 时 enable-dns-routing 仍然听用户设置开关', () {
      final optionsOff = getDefaultConfigOptions(
        isSmart: false,
        settings: const NetworkSettings(enableDnsRouting: false),
      );
      expect(optionsOff['enable-dns-routing'], isFalse);

      final optionsOn = getDefaultConfigOptions(
        isSmart: false,
        settings: const NetworkSettings(enableDnsRouting: true),
      );
      expect(optionsOn['enable-dns-routing'], isTrue);
    });
  });
}
