import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/temp_dirs.dart';

/// 按内核配置构建器（BuildConfig）的口径算主选择组 / 自动选择组的节点成员：
/// 跳过 direct / block / dns / selector / urltest / custom 类型，跳过 tag 含
/// 隐藏标记的出站。自动选择组的成员就是这份列表，主选择组是 auto 加这份列表。
List<String> _kernelGroupMembers(Map<String, dynamic> cfg) => [
  for (final o in cfg['outbounds'] as List)
    if (!const {
          'direct',
          'block',
          'dns',
          'selector',
          'urltest',
          'custom',
        }.contains((o as Map)['type']) &&
        !(o['tag'] as String).contains('§hide§'))
      o['tag'] as String,
];

Future<File> _writeProfile(Directory dir, Map<String, dynamic> cfg) async {
  final f = File('${dir.path}/profile.json');
  await f.writeAsString(jsonEncode(cfg));
  return f;
}

void main() {
  group('RuntimeConfigBuilder', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rcb_test_');
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmp);
    });

    // route/dns 的 rule_set 注入/剥离曾经在这里做，但真机验证证实这个 sing-box
    // fork 的 config.BuildConfig() 无条件丢弃/重建 profile 自带的 route 块——
    // 不管这里往 cfg['route'] 写什么都不会真正生效。真正生效的分流机制搬到了
    // getDefaultConfigOptions 的 isSmart 参数（configOptions.rules），见
    // default_config_options_test.dart。这里改成断言 route/dns 原样透传。
    test('profile 自带的 route/dns 原样透传，不再被改写', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        'route': {
          'rule_set': [
            {
              'tag': 'remote',
              'type': 'remote',
              'url': 'https://blocked.example/rs.srs',
            },
          ],
          'rules': [
            {
              'rule_set': ['remote'],
              'outbound': 'direct',
            },
            {'domain': 'example.com', 'outbound': 'proxy'},
          ],
        },
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      final route = cfg['route'] as Map<String, dynamic>;
      expect(route['rule_set'], hasLength(1));
      final routeRules = (route['rules'] as List<dynamic>)
          .cast<Map<dynamic, dynamic>>();
      expect(routeRules.any((r) => r['rule_set'] != null), isTrue);
      expect(routeRules.any((r) => r['domain'] == 'example.com'), isTrue);
    });

    test('桌面端剥离 tun + mixed inbound', () async {
      // _isDesktop 用 io.Platform，所以在移动平台测试时这条会失效
      if (Platform.isAndroid || Platform.isIOS) return;
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in'},
          {'type': 'mixed', 'tag': 'mixed-in', 'listen_port': 2080},
          {'type': 'socks', 'tag': 'socks-in', 'listen_port': 2081},
        ],
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      final inbounds = (cfg['inbounds'] as List<dynamic>)
          .cast<Map<dynamic, dynamic>>();
      expect(inbounds.any((i) => i['type'] == 'tun'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'mixed'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'socks'), isTrue);
    });

    // 真机验收 BUG-B：订阅里的 tun inbound 留在运行配置里，内核配置构建器又按
    // enable-tun 再 append 一个，VPN 每次启动 establish() 两次，tun 转发偶发全拒。
    // 真机验收 BUG-3：「仅线路」跑在纯代理 Service 里，留着 tun 内核启动即失败。
    // 所以 tun 与 mixed 一律剥，tun 只由 enable-tun 交给内核创建（恰好一个）。
    test('tun 与 mixed inbound 一律剥掉：tun 只由 enable-tun 交给内核创建', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in'},
          {'type': 'mixed', 'tag': 'mixed-in', 'listen_port': 2080},
          {'type': 'socks', 'tag': 'keep-me', 'listen_port': 1080},
        ],
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
      final inbounds = (cfg['inbounds'] as List<dynamic>)
          .cast<Map<dynamic, dynamic>>();
      expect(inbounds.map((i) => i['type']), ['socks']);
    });

    test('输出文件名固定 runtime-config.json', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'p', 'outbounds': <String>[]},
        ],
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
      );

      expect(out.path, '${tmp.path}/runtime-config.json');
      expect(await out.exists(), isTrue);
    });

    test('不再往配置里写 dns：传不传 remoteDnsAddress、传什么值，输出字节相同', () async {
      final profile = {
        'outbounds': [
          {'type': 'shadowsocks', 'tag': 'hk'},
        ],
      };
      final base = await _writeProfile(tmp, profile);
      Future<String> run(String? remote, String name) async {
        final out = await RuntimeConfigBuilder().build(
          baseProfile: base,
          workingDir: tmp,
          remoteDnsAddress: remote,
          outputFileName: name,
        );
        return out.readAsString();
      }

      final none = await run(null, 'a.json');
      expect(await run('', 'b.json'), none);
      expect(await run('https://dns.google/dns-query', 'c.json'), none);
      expect(await run('tls://1.1.1.1', 'd.json'), none);
      final cfg = jsonDecode(none) as Map<String, dynamic>;
      expect(cfg.containsKey('dns'), isFalse, reason: '内核重建 dns，写进去是死数据');
    });

    test('profile 自带的 dns 块原样保留，不补不改', () async {
      final dns = {
        'servers': [
          {'tag': 'remote', 'address': 'udp://9.9.9.9'},
        ],
      };
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'shadowsocks', 'tag': 'hk'},
        ],
        'dns': dns,
      });
      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
        remoteDnsAddress: 'https://1.1.1.1/dns-query',
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
      expect(cfg['dns'], dns);
    });

    test('非法 JSON 抛 FormatException', () async {
      final base = File('${tmp.path}/profile.json');
      await base.writeAsString('not json at all');

      expect(
        () => RuntimeConfigBuilder().build(baseProfile: base, workingDir: tmp),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('runtimeSelectorDefaults：运行时选择组默认值', () {
    test('内核重建的主选择组 select：默认自动选择组 auto（成员 auto + 全部节点）', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': ['hk', 'sg'],
            'default': 'sg',
          },
          {
            'type': 'urltest',
            'tag': 'u',
            'outbounds': ['hk', 'sg'],
          },
          {'type': 'vless', 'tag': 'hk'},
          {'type': 'vless', 'tag': 'sg'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      });
      expect(d[kRuntimeMainSelectorTag], kRuntimeAutoGroupTag);
      expect(d['proxy'], 'sg', reason: '配置里的 selector：default 字段');
      expect(d.containsKey('u'), isFalse, reason: 'urltest 没有可还原的默认值');
    });

    test('selector 没写 default：取 outbounds 第一项；写了但不是成员：默认值未知（内核会报错，不回退）', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'a',
            'outbounds': ['x', 'y'],
          },
          {
            'type': 'selector',
            'tag': 'b',
            'outbounds': ['x', 'y'],
            'default': 'gone',
          },
          {'type': 'selector', 'tag': 'empty', 'outbounds': <String>[]},
        ],
      });
      expect(d['a'], 'x');
      expect(d.containsKey('b'), isFalse);
      expect(d.containsKey('empty'), isFalse);
    });

    test('节点带默认标记：主选择组默认值是该节点的真实 tag（不是标记字面值）', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {'type': 'vless', 'tag': 'hk'},
          {'type': 'vless', 'tag': 'sg §default§'},
        ],
      });
      expect(d[kRuntimeMainSelectorTag], 'sg §default§');
    });

    test('带默认标记的节点同时带隐藏标记：不是成员，默认回到 auto', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {'type': 'vless', 'tag': 'hk'},
          {'type': 'vless', 'tag': 'sg §default§ §hide§'},
        ],
      });
      expect(d[kRuntimeMainSelectorTag], kRuntimeAutoGroupTag);
    });

    test('多个节点带默认标记：取第一个（与内核同口径）', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {'type': 'vless', 'tag': 'a §default§'},
          {'type': 'vless', 'tag': 'b §default§'},
        ],
      });
      expect(d[kRuntimeMainSelectorTag], 'a §default§');
    });

    test('订阅自带同名主选择组：重建后的默认值才算数，不残留旧 selector 的 default', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {
            'type': 'selector',
            'tag': kRuntimeMainSelectorTag,
            'outbounds': ['hk §default§', 'sg'],
            'default': 'sg',
          },
          {'type': 'vless', 'tag': 'hk §default§'},
          {'type': 'vless', 'tag': 'sg'},
        ],
      });
      expect(
        d[kRuntimeMainSelectorTag],
        'hk §default§',
        reason: '内核重建主选择组，旧 selector 的 default: sg 不再代表它',
      );
    });

    test('没有任何节点：主选择组只有 auto，默认 auto', () {
      expect(runtimeSelectorDefaults({'outbounds': <Object>[]}), {
        kRuntimeMainSelectorTag: kRuntimeAutoGroupTag,
      });
    });
  });
  group('订阅信息条目：不进主选择组 / 自动选择组', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rcb_info_test_');
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmp);
    });

    const info = '🌐 官网地址：ncink.cc';
    const hk = '🇭🇰 香港01-BGP|IEPL中继';
    const sg = '🇸🇬 狮城01-BGP|IEPL中继';
    const hiddenInfo = '$info $kHideNodeMarker';

    Map<String, dynamic> subscription() => {
      'dns': {
        'servers': [
          {'tag': 'remote', 'address': 'https://1.1.1.1/dns-query'},
          {'tag': 'via-info', 'address': '8.8.8.8', 'detour': info},
        ],
      },
      'outbounds': [
        {
          'type': 'selector',
          'tag': '节点选择',
          'outbounds': ['自动选择', info, hk, sg],
          'default': info,
        },
        {
          'type': 'urltest',
          'tag': '自动选择',
          'outbounds': [info, hk, sg],
        },
        {'type': 'vless', 'tag': info, 'server': 'a.example', 'port': 1},
        {'type': 'vless', 'tag': hk, 'server': 'a.example', 'port': 1},
        {'type': 'vless', 'tag': sg, 'server': 'b.example', 'port': 2},
        {'type': 'vless', 'tag': 'chain', 'detour': info},
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'final': info,
        'rules': [
          {'domain': 'example.com', 'outbound': info},
        ],
      },
    };

    test('构建结果：信息条目打上隐藏标记，内核口径下不是任何分组的成员', () async {
      final base = await _writeProfile(tmp, subscription());
      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;
      final tags = [
        for (final o in cfg['outbounds'] as List) (o as Map)['tag'],
      ];
      expect(tags, contains(hiddenInfo));
      expect(tags, isNot(contains(info)));
      expect(_kernelGroupMembers(cfg), [hk, sg, 'chain']);
      expect(runtimeSelectorDefaults(cfg)[kRuntimeMainSelectorTag], 'auto');
    });

    test('引用旧 tag 的地方一并改名，配置自洽', () {
      final cfg = subscription();
      final renames = hideSubscriptionInfoOutbounds(cfg);
      expect(renames, {info: hiddenInfo});

      final byTag = {
        for (final o in cfg['outbounds'] as List) (o as Map)['tag']: o,
      };
      expect(byTag['节点选择']!['outbounds'], ['自动选择', hiddenInfo, hk, sg]);
      expect(byTag['节点选择']!['default'], hiddenInfo);
      expect(byTag['自动选择']!['outbounds'], [hiddenInfo, hk, sg]);
      expect(byTag['chain']!['detour'], hiddenInfo);
      expect(byTag[hk]!['tag'], hk, reason: '真实节点不动');
      final route = cfg['route'] as Map;
      expect(route['final'], hiddenInfo);
      expect(((route['rules'] as List)[0] as Map)['outbound'], hiddenInfo);
      final servers = (cfg['dns'] as Map)['servers'] as List;
      expect((servers[1] as Map)['detour'], hiddenInfo);
      expect((servers[0] as Map).containsKey('detour'), isFalse);
    });

    test('改名后的 tag 已被占用：继续追加标记，不撞名', () {
      final cfg = <String, dynamic>{
        'outbounds': [
          {'type': 'vless', 'tag': info},
          {'type': 'vless', 'tag': hiddenInfo},
          {'type': 'vless', 'tag': hk},
        ],
      };
      final renames = hideSubscriptionInfoOutbounds(cfg);
      expect(renames[info], '$hiddenInfo$kHideNodeMarker');
      final tags = [
        for (final o in cfg['outbounds'] as List) (o as Map)['tag'],
      ];
      expect(tags.toSet().length, tags.length);
    });

    test('全是信息条目：不改（宁可留着，也不能让主选择组只剩空的自动选择组）', () {
      final cfg = <String, dynamic>{
        'outbounds': [
          {'type': 'vless', 'tag': info},
          {'type': 'vless', 'tag': '剩余流量：1 GB'},
          {'type': 'direct', 'tag': 'direct'},
        ],
      };
      expect(hideSubscriptionInfoOutbounds(cfg), isEmpty);
      expect(_kernelGroupMembers(cfg), [info, '剩余流量：1 GB']);
    });

    test('runtimeSelectorDefaults 与构建器同口径：未标记的配置里信息条目同样不算成员', () {
      // 主选择组成员不含信息条目：它带默认标记也不会成为默认值。
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {'type': 'vless', 'tag': '官网地址：a.cc §default§'},
          {'type': 'vless', 'tag': hk},
        ],
      });
      expect(d[kRuntimeMainSelectorTag], 'auto');
    });
  });
}
