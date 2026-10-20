import 'dart:convert';

import 'package:clashmiao/domain/routing/data/config_parser.dart';
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

    test('成员是端点 / 分组时认得类型：端点 = wireguard，auto = urltest', () {
      final cfg = jsonEncode({
        'outbounds': [
          {
            'type': 'selector',
            'tag': 'select',
            'outbounds': ['auto', 'hk', 'wg-hk'],
            'default': 'auto',
          },
          {
            'type': 'urltest',
            'tag': 'auto',
            'outbounds': ['hk', 'wg-hk'],
          },
          {'type': 'shadowsocks', 'tag': 'hk'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg-hk'},
        ],
      });

      final groups = ConfigParser.parseConfig(cfg);
      expect(groups.map((g) => g.tag), ['select', 'auto']);
      final select = groups.first;
      expect(select.items.map((i) => i.tag), ['auto', 'hk', 'wg-hk']);
      expect(select.items.map((i) => i.type), [
        'urltest',
        'shadowsocks',
        'wireguard',
      ]);
      expect(select.items.any((i) => i.type == 'unknown'), isFalse);
      expect(select.selected, 'auto');
    });

    test('只有端点、没有分组：返回空列表，不抛', () {
      final cfg = jsonEncode({
        'outbounds': <Object>[],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg-hk'},
        ],
      });
      expect(ConfigParser.parseConfig(cfg), isEmpty);
    });

    test('分组本身放在 endpoints 数组里也会被遍历（完整集合，不是叶子视图）', () {
      final cfg = jsonEncode({
        'outbounds': [
          {'type': 'vless', 'tag': 'v'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': 'wg'},
          {
            'type': 'selector',
            'tag': 'g',
            'outbounds': ['v', 'wg'],
          },
        ],
      });
      final groups = ConfigParser.parseConfig(cfg);
      expect(groups.single.tag, 'g');
      expect(groups.single.items.map((i) => i.type), ['vless', 'wireguard']);
    });
  });
}
