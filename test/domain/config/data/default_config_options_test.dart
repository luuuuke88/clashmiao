import 'package:clashmiao/domain/config/data/cn_direct_rules.dart';
import 'package:clashmiao/domain/config/data/default_config_options.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/application/service_mode.dart';
import 'package:clashmiao/domain/config/model/advanced_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按内核 BuildConfig 的口径推出「某个域名由哪台 DNS 服务器解析」。
///
/// 内核丢弃 profile 自带的 dns 块，自己建 dns-remote（remote-dns-address，经主
/// 选择组走代理）、dns-direct（direct-dns-address，经 direct 出站）等服务器；
/// `enable-dns-routing` 为真时，`outbound: bypass` 的规则逐条变成指向 dns-direct
/// 的 DNS 规则（`full:` → domain，`domain:` → domain_suffix，`regexp:` →
/// domain_regex），其余一律落到 final：dns-remote。返回 (服务器 tag, 地址)。
(String, String) _kernelDnsFor(Map<String, dynamic> options, String domain) {
  final direct = ('dns-direct', options['direct-dns-address'] as String);
  final remote = ('dns-remote', options['remote-dns-address'] as String);
  if (options['enable-dns-routing'] != true) return remote;
  for (final rule in options['rules'] as List) {
    final r = rule as Map<String, dynamic>;
    if (r['outbound'] != 'bypass') continue;
    final domains = (r['domains'] as String?) ?? '';
    if (domains.isEmpty) continue;
    for (final item in domains.split(',')) {
      final matched = switch (item) {
        _ when item.startsWith('full:') => domain == item.substring(5),
        _ when item.startsWith('domain:') =>
          domain == item.substring(7) ||
              domain.endsWith('.${item.substring(7)}'),
        _ when item.startsWith('regexp:') => RegExp(
          item.substring(7),
        ).hasMatch(domain),
        _ => false,
      };
      if (matched) return direct;
    }
  }
  return remote;
}

void main() {
  group('DNS：直连域名由国内解析器解析，代理域名走远程 DNS', () {
    const cnDomains = [
      'www.baidu.com',
      'www.taobao.com',
      'g.alicdn.com',
      'www.qq.com',
      'www.gov.cn',
    ];
    const proxiedDomains = [
      'www.google.com',
      'www.youtube.com',
      'www.gstatic.com',
      'www.google.cn',
      'github.com',
    ];

    test('默认设置：直连 DNS 是 AliDNS 223.5.5.5，远程 DNS 不变', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      expect(options['direct-dns-address'], '223.5.5.5');
      expect(options['remote-dns-address'], 'https://1.1.1.1/dns-query');
      expect(options['enable-dns-routing'], isTrue);
    });

    test('智能分流：国内直连域名 → dns-direct（223.5.5.5）', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      for (final d in cnDomains) {
        expect(_kernelDnsFor(options, d), (
          'dns-direct',
          '223.5.5.5',
        ), reason: d);
      }
    });

    test('智能分流：代理域名 → dns-remote（经代理，不泄漏给国内解析器）', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      for (final d in proxiedDomains) {
        expect(_kernelDnsFor(options, d), (
          'dns-remote',
          'https://1.1.1.1/dns-query',
        ), reason: d);
      }
    });

    test('全局模式：没有直连规则，所有域名都走远程 DNS', () {
      final options = getDefaultConfigOptions(
        isSmart: false,
        settings: const NetworkSettings(),
      );
      for (final d in [...cnDomains, ...proxiedDomains]) {
        expect(_kernelDnsFor(options, d).$1, 'dns-remote', reason: d);
      }
    });

    test('用户手动设置的直连 DNS 原样生效', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(directDnsAddress: '119.29.29.29'),
      );
      expect(options['direct-dns-address'], '119.29.29.29');
      expect(_kernelDnsFor(options, 'www.baidu.com'), (
        'dns-direct',
        '119.29.29.29',
      ));
    });
  });

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
      expect(domains, containsAll(['domain:baidu.com', 'domain:qq.com']));
      // 顶级域 `cn` 不再是裸后缀：排除表把它改写成跳过谷歌系 .cn 域名的正则。
      expect(domains, isNot(contains('domain:cn')));
      expect(
        domains,
        containsAll(cnDirectDomainRegexes.map((r) => 'regexp:$r')),
      );
    });

    // 这条曾经只有 66 个手写域名后缀——国内 IP 上的站靠 IP 规则能兜住，但用
    // 海外 CDN 的国内服务、以及 DNS 解析阶段都会走代理。现在改成完整反编译
    // 自 geosite-cn.srs 的清单。
    test('域名规则用的是完整反编译清单，不是手写摘要', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      final rules = (options['rules'] as List).cast<Map<String, dynamic>>();
      final domains =
          (rules.firstWhere((r) => r['domains'] != null)['domains'] as String)
              .split(',');

      expect(
        domains.length,
        cnDirectDomains.length +
            cnDirectDomainSuffixes.length +
            cnDirectDomainRegexes.length,
        reason: '三个清单必须完整注入，不能有截断',
      );
      expect(
        cnDirectDomainSuffixes.length,
        greaterThan(5000),
        reason: '完整的 geosite-cn 后缀清单是数千条量级；掉回三位数说明退回了手写摘要',
      );
      expect(cnDirectDomains, isNotEmpty, reason: '精确匹配清单不能为空');
    });

    // 前缀语义不同不能混用：`full:` 进内核的 Domain（精确匹配），
    // `domain:` 进 DomainSuffix（后缀匹配），`regexp:` 进 DomainRegex。搞反了
    // 会让精确规则变成后缀规则，把不该直连的子域一起放走。
    test('精确域名用 full: 前缀，后缀用 domain: 前缀，正则用 regexp: 前缀', () {
      final options = getDefaultConfigOptions(
        isSmart: true,
        settings: const NetworkSettings(),
      );
      final rules = (options['rules'] as List).cast<Map<String, dynamic>>();
      final domains =
          (rules.firstWhere((r) => r['domains'] != null)['domains'] as String)
              .split(',');

      expect(domains, contains('full:${cnDirectDomains.first}'));
      expect(domains, contains('domain:${cnDirectDomainSuffixes.first}'));
      expect(domains, contains('regexp:${cnDirectDomainRegexes.first}'));
      expect(
        domains.where(
          (d) =>
              !d.startsWith('full:') &&
              !d.startsWith('domain:') &&
              !d.startsWith('regexp:'),
        ),
        isEmpty,
        reason: '每一条都必须带前缀，裸域名会被内核的 makeDomainRule 直接忽略',
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

    // 内核把直连规则翻译成 DNS 规则这一步受 enable-dns-routing 控制，
    // isSmart=true 时上面那两条直连规则要真正生效，它必须为 true——即使用户在
    // 设置页把"DNS 路由"这个开关关掉了，也不能连带把智能分流的直连规则一起废掉。
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

  group('订阅级远程 DNS 覆盖（高级配置的 remoteDnsOverride）', () {
    const settings = NetworkSettings(
      remoteDnsAddress: 'https://1.1.1.1/dns-query',
    );

    test('覆盖非空：写进 remote-dns-address，优先于全局设置', () {
      final options = getDefaultConfigOptions(
        settings: settings,
        advancedConfig: const AdvancedConfig(
          remoteDnsOverride: 'tls://dot.example.net',
        ),
      );
      expect(options['remote-dns-address'], 'tls://dot.example.net');
    });

    test('覆盖为空串或没有高级配置：沿用全局设置', () {
      expect(
        getDefaultConfigOptions(
          settings: settings,
          advancedConfig: const AdvancedConfig(remoteDnsOverride: ''),
        )['remote-dns-address'],
        'https://1.1.1.1/dns-query',
      );
      expect(
        getDefaultConfigOptions(
          settings: settings,
          advancedConfig: const AdvancedConfig(),
        )['remote-dns-address'],
        'https://1.1.1.1/dns-query',
      );
      expect(
        getDefaultConfigOptions(settings: settings)['remote-dns-address'],
        'https://1.1.1.1/dns-query',
      );
    });

    test('覆盖只动远程 DNS：直连 DNS 与其余键不变', () {
      final base = getDefaultConfigOptions(settings: settings);
      final overridden = getDefaultConfigOptions(
        settings: settings,
        advancedConfig: const AdvancedConfig(
          remoteDnsOverride: 'udp://9.9.9.9',
        ),
      );
      expect(
        {...overridden}..remove('remote-dns-address'),
        {...base}..remove('remote-dns-address'),
      );
    });
  });

  group('平台口径（服务模式平台，不是宿主机的 Platform）', () {
    tearDown(() => debugServiceModePlatformOverride = null);

    test('Android：默认 VPN 档 → enable-tun 真、不设系统代理', () {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(),
      );
      expect(options['enable-tun'], isTrue);
      expect(options['set-system-proxy'], isFalse);
    });

    test('Android 仅线路：enable-tun 假（两个开关都关）', () {
      debugServiceModePlatformOverride = ServiceModePlatform.android;
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(
          enableTun: false,
          setSystemProxy: false,
        ),
      );
      expect(options['enable-tun'], isFalse);
      expect(options['set-system-proxy'], isFalse);
    });

    test('iOS：恒 VPN，不设系统代理', () {
      debugServiceModePlatformOverride = ServiceModePlatform.ios;
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(enableTun: false, setSystemProxy: true),
      );
      expect(options['enable-tun'], isTrue);
      expect(options['set-system-proxy'], isFalse);
    });

    test('桌面：尊重显式设置，系统代理可开', () {
      debugServiceModePlatformOverride = ServiceModePlatform.desktop;
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(enableTun: false, setSystemProxy: true),
      );
      expect(options['enable-tun'], isFalse);
      expect(options['set-system-proxy'], isTrue);
    });
  });

  group('界面隐藏的选项仍然照常产出（只隐藏入口，不改持久化值）', () {
    test('block-ads / padding / 混合 SNI / 噪声：存档里的值原样进选项', () {
      final options = getDefaultConfigOptions(
        settings: const NetworkSettings(
          blockAds: true,
          enableTlsPadding: true,
          enableTlsMixedSniCase: true,
          tlsFragmentSize: '5-9',
          warpNoise: '2-4',
        ),
      );
      expect(options['block-ads'], isTrue);
      final tls = options['tls-tricks'] as Map<String, dynamic>;
      expect(tls['enable-padding'], isTrue);
      expect(tls['mixed-sni-case'], isTrue);
      expect(tls['fragment-size'], '5-9');
      expect((options['warp'] as Map<String, dynamic>)['noise'], '2-4');
    });
  });
}
