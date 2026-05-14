import 'dart:convert';

import 'package:clashmiao/core/utils/config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigParser.parseConfig', () {
    test('标准 selector group + 子节点解析', () {
      final cfg = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'Proxy',
            'outbounds': ['n1', 'n2'],
            'default': 'n2',
          },
          {'type': 'vless', 'tag': 'n1'},
          {'type': 'trojan', 'tag': 'n2'},
        ],
      });

      final groups = ConfigParser.parseConfig(cfg);
      expect(groups, hasLength(1));
      expect(groups.first.tag, 'Proxy');
      expect(groups.first.selected, 'n2');
      expect(groups.first.items.map((i) => i.tag), ['n1', 'n2']);
      expect(groups.first.items.map((i) => i.type), ['vless', 'trojan']);
    });

    test('缺 outbounds 字段返回空列表', () {
      expect(ConfigParser.parseConfig('{}'), isEmpty);
      expect(ConfigParser.parseConfig('{"outbounds": []}'), isEmpty);
    });

    test('混合 selector + urltest，只跳过非 group 类型节点', () {
      final cfg = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'Manual',
            'outbounds': ['n1'],
          },
          {
            'type': 'urltest',
            'tag': 'Auto',
            'outbounds': ['n1', 'n2'],
          },
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'vless', 'tag': 'n1'},
          {'type': 'vless', 'tag': 'n2'},
        ],
      });

      final groups = ConfigParser.parseConfig(cfg);
      expect(groups.map((g) => g.tag), ['Manual', 'Auto']);
    });
  });
}
