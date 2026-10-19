import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/temp_dirs.dart';

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

    // 真机验收 BUG-3：切到「仅线路」后协调器换成纯代理 Service，但运行时配置里
    // 仍带着 tun inbound，内核启动失败（openTun called on a non-VPN service）。
    test('按服务模式：不保留 tun 时剥掉 tun，保留时留下（mixed 始终剥）', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        'inbounds': [
          {'type': 'tun', 'tag': 'tun-in'},
          {'type': 'mixed', 'tag': 'mixed-in', 'listen_port': 2080},
        ],
      });

      Future<List<Map<dynamic, dynamic>>> inbounds(bool keepTun) async {
        final out = await RuntimeConfigBuilder().build(
          baseProfile: base,
          workingDir: tmp,
          keepTunInbound: keepTun,
        );
        final cfg =
            jsonDecode(await out.readAsString()) as Map<String, dynamic>;
        return (cfg['inbounds'] as List<dynamic>).cast<Map<dynamic, dynamic>>();
      }

      expect((await inbounds(false)).map((i) => i['type']), isEmpty);
      expect((await inbounds(true)).map((i) => i['type']), ['tun']);
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

    test('节点带默认标记但没有恰好叫这个标记的成员：主选择组默认值未知（内核启动报错，不回退）', () {
      final d = runtimeSelectorDefaults({
        'outbounds': [
          {'type': 'vless', 'tag': 'hk §default§'},
          {'type': 'vless', 'tag': 'sg §hide§'},
        ],
      });
      expect(d.containsKey(kRuntimeMainSelectorTag), isFalse);
    });

    test('没有任何节点：主选择组只有 auto，默认 auto', () {
      expect(runtimeSelectorDefaults({'outbounds': <Object>[]}), {
        kRuntimeMainSelectorTag: kRuntimeAutoGroupTag,
      });
    });
  });
}
