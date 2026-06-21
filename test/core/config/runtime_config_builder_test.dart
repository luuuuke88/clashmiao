import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/config/runtime_config_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('smart 模式注入 cn rule-set + direct 路由 + local DNS', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': ['n1'],
          },
        ],
        'route': {'rules': <Map<String, dynamic>>[]},
        'dns': {'rules': <Map<String, dynamic>>[]},
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        isSmart: true,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      final ruleSets = (cfg['route']['rule_set'] as List).cast<Map>();
      expect(ruleSets, hasLength(2));
      expect(
        ruleSets.map((e) => e['tag']),
        containsAll(['geoip-cn', 'geosite-cn']),
      );

      // 路径必须绝对 —— Android 上 sing-box CWD 跟 Flutter workingDir 不一致，
      // 相对路径会让 rule-set 静默失败，结果智能模式看起来跟全局一模一样。
      for (final rs in ruleSets) {
        expect(
          p.isAbsolute(rs['path'] as String),
          isTrue,
          reason: 'rule-set path 必须绝对：${rs['path']}',
        );
        expect(rs['path'], contains(tmp.path));
      }

      final routeRules = (cfg['route']['rules'] as List).cast<Map>();
      expect(routeRules.first['outbound'], 'direct');
      expect(
        routeRules.first['rule_set'] as List,
        unorderedEquals(['geoip-cn', 'geosite-cn']),
      );
      expect(routeRules[1]['outbound'], 'direct');
      expect(
        routeRules[1]['domain_suffix'] as List,
        unorderedEquals(['cn', '中国', '公司', '网络']),
      );

      final dnsRules = (cfg['dns']['rules'] as List).cast<Map>();
      expect(dnsRules.first['server'], 'local');
      expect(dnsRules[1]['server'], 'local');
      expect(
        dnsRules[1]['domain_suffix'] as List,
        unorderedEquals(['cn', '中国', '公司', '网络']),
      );
    });

    test('global 模式剥离所有 rule_set 引用', () async {
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
        'dns': {
          'rules': [
            {
              'rule_set': ['remote'],
              'server': 'local',
            },
            {'domain': 'foo.bar', 'server': 'remote'},
          ],
        },
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        isSmart: false,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      expect(cfg['route']['rule_set'], isEmpty);
      final routeRules = (cfg['route']['rules'] as List).cast<Map>();
      expect(routeRules.any((r) => r['rule_set'] != null), isFalse);
      expect(routeRules.any((r) => r['domain'] == 'example.com'), isTrue);

      final dnsRules = (cfg['dns']['rules'] as List).cast<Map>();
      expect(dnsRules.any((r) => r['rule_set'] != null), isFalse);
      expect(dnsRules.any((r) => r['domain'] == 'foo.bar'), isTrue);
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
        isSmart: false,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      final inbounds = (cfg['inbounds'] as List).cast<Map>();
      expect(inbounds.any((i) => i['type'] == 'tun'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'mixed'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'socks'), isTrue);
    });

    test('smart 模式即使 route/dns 字段不存在也兜底创建', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'proxy', 'outbounds': <String>[]},
        ],
        // 故意不写 route / dns
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        isSmart: true,
        workingDir: tmp,
      );
      final cfg = jsonDecode(await out.readAsString()) as Map<String, dynamic>;

      expect(cfg['route']['rule_set'], hasLength(2));
      expect((cfg['route']['rules'] as List).first['outbound'], 'direct');
      expect((cfg['dns']['rules'] as List).first['server'], 'local');
      expect(
        (cfg['route']['rules'] as List)[1]['domain_suffix'],
        contains('cn'),
      );
      expect((cfg['dns']['rules'] as List)[1]['domain_suffix'], contains('cn'));
    });

    test('输出文件名固定 runtime-config.json', () async {
      final base = await _writeProfile(tmp, {
        'outbounds': [
          {'type': 'selector', 'tag': 'p', 'outbounds': <String>[]},
        ],
      });

      final out = await RuntimeConfigBuilder().build(
        baseProfile: base,
        isSmart: true,
        workingDir: tmp,
      );

      expect(out.path, '${tmp.path}/runtime-config.json');
      expect(await out.exists(), isTrue);
    });

    test('非法 JSON 抛 FormatException', () async {
      final base = File('${tmp.path}/profile.json');
      await base.writeAsString('not json at all');

      expect(
        () => RuntimeConfigBuilder().build(
          baseProfile: base,
          isSmart: true,
          workingDir: tmp,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
