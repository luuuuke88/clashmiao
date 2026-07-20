import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/config/runtime_config_builder.dart';
import 'package:flutter_test/flutter_test.dart';

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

      expect(cfg['route']['rule_set'], hasLength(1));
      final routeRules = (cfg['route']['rules'] as List).cast<Map>();
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

      final inbounds = (cfg['inbounds'] as List).cast<Map>();
      expect(inbounds.any((i) => i['type'] == 'tun'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'mixed'), isFalse);
      expect(inbounds.any((i) => i['type'] == 'socks'), isTrue);
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
}
