import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/model/profile_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _profile({
  List<Object?> outbounds = const [],
  List<Object?>? endpoints,
}) => {'outbounds': outbounds, 'endpoints': ?endpoints};

void main() {
  group('profileEntities：完整集合（出站 ∪ 端点，含分组）', () {
    test('出站在前、端点在后，各自保持顺序，带来源', () {
      final all = profileEntities(
        _profile(
          outbounds: [
            {'type': 'selector', 'tag': 'sel'},
            {'type': 'vless', 'tag': 'v'},
            {'type': 'direct', 'tag': 'direct'},
          ],
          endpoints: [
            {'type': 'wireguard', 'tag': 'wg'},
          ],
        ),
      );
      expect([for (final e in all) e.tag], ['sel', 'v', 'direct', 'wg']);
      expect(
        [for (final e in all) e.type],
        ['selector', 'vless', 'direct', 'wireguard'],
      );
      expect(
        [for (final e in all) e.source],
        [
          EntitySource.outbound,
          EntitySource.outbound,
          EntitySource.outbound,
          EntitySource.endpoint,
        ],
      );
      expect(all.last.isEndpoint, isTrue);
    });

    test('raw 就是原始 Map：改它就是改配置', () {
      final cfg = _profile(
        endpoints: [
          {'type': 'wireguard', 'tag': 'wg'},
        ],
      );
      profileEntities(cfg).single.raw['tag'] = 'renamed';
      expect(((cfg['endpoints'] as List).single as Map)['tag'], 'renamed');
    });

    test('表驱动：畸形输入不抛，只是跳过', () {
      final cases = <String, Map<String, dynamic>>{
        '空配置': {},
        'outbounds 不是列表': {'outbounds': 'x', 'endpoints': 3},
        '元素不是 Map': {
          'outbounds': ['a', 1, null],
        },
        '没有 type': {
          'outbounds': [
            {'tag': 'x'},
          ],
        },
        'type 不是字符串': {
          'outbounds': [
            {'type': 1, 'tag': 'x'},
          ],
        },
      };
      for (final entry in cases.entries) {
        expect(profileEntities(entry.value), isEmpty, reason: entry.key);
        expect(profileNodeCount(entry.value), 0, reason: entry.key);
      }
    });

    test('没有 tag 的实体保留（tag 为空串），不影响计数', () {
      final cfg = _profile(
        outbounds: [
          {'type': 'vless'},
        ],
      );
      expect(profileEntities(cfg).single.tag, '');
      expect(profileNodeCount(cfg), 1);
    });
  });

  group('profileLeafNodes：叶子视图（真实可连的节点，含端点）', () {
    // 表驱动：每个类型是不是叶子。大小写、`-` / `_` 不敏感。
    const table = <String, bool>{
      'vless': true,
      'vmess': true,
      'trojan': true,
      'shadowsocks': true,
      'hysteria2': true,
      'tuic': true,
      'anytls': true,
      'wireguard': true,
      'selector': false,
      'urltest': false,
      'url_test': false,
      'url-test': false,
      'URLTest': false,
      'select': false,
      'direct': false,
      'block': false,
      'dns': false,
      'custom': false,
    };
    for (final entry in table.entries) {
      test('${entry.key} → ${entry.value ? '叶子' : '非叶子'}', () {
        expect(isLeafType(entry.key), entry.value);
        final cfg = _profile(
          outbounds: [
            {'type': entry.key, 'tag': 't'},
          ],
        );
        expect(profileLeafNodes(cfg).length, entry.value ? 1 : 0);
        // 端点里同样适用。
        final epCfg = _profile(
          endpoints: [
            {'type': entry.key, 'tag': 't'},
          ],
        );
        expect(profileLeafNodes(epCfg).length, entry.value ? 1 : 0);
      });
    }

    test('混合配置：分组 / 直连不在叶子里，端点在', () {
      final cfg = _profile(
        outbounds: [
          {'type': 'selector', 'tag': 'sel'},
          {'type': 'urltest', 'tag': 'auto'},
          {'type': 'vless', 'tag': 'v'},
          {'type': 'direct', 'tag': 'direct'},
          {'type': 'block', 'tag': 'block'},
          {'type': 'dns', 'tag': 'dns-out'},
        ],
        endpoints: [
          {'type': 'wireguard', 'tag': 'wg'},
        ],
      );
      expect([for (final n in profileLeafNodes(cfg)) n.tag], ['v', 'wg']);
      expect(profileNodeCount(cfg), 2);
      expect(profileEntities(cfg), hasLength(7), reason: '两个视图不是一回事');
    });

    test('outbounds 为空而端点非空：计数非零', () {
      expect(
        profileNodeCount(
          _profile(
            endpoints: [
              {'type': 'wireguard', 'tag': 'wg'},
            ],
          ),
        ),
        1,
      );
    });

    test('只有 direct / 只有分组：计数为零', () {
      expect(
        profileNodeCount(
          _profile(
            outbounds: [
              {'type': 'direct', 'tag': 'direct'},
            ],
          ),
        ),
        0,
      );
      expect(
        profileNodeCount(
          _profile(
            outbounds: [
              {
                'type': 'selector',
                'tag': 'sel',
                'outbounds': <String>['a'],
              },
              {
                'type': 'urltest',
                'tag': 'auto',
                'outbounds': <String>['a'],
              },
            ],
          ),
        ),
        0,
      );
    });
  });

  group('旧形态清单与 Go 共用夹具 legacy-shapes.json', () {
    final fixture = jsonDecode(
      File('kernel/testdata/shared/legacy-shapes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final shapes = (fixture['shapes'] as List).cast<Map<String, dynamic>>();

    test('夹具非空，且两种取值都有（否则这条测试什么也没钉住）', () {
      expect(shapes.length, greaterThan(8));
      expect(shapes.any((s) => s['needsCleaning'] == true), isTrue);
      expect(shapes.any((s) => s['needsCleaning'] == false), isTrue);
    });

    for (final shape in shapes) {
      test(
        '${shape['name']}：outboundNeedsCleaning = ${shape['needsCleaning']}',
        () {
          final json = shape['json'] as Map<String, dynamic>;
          expect(outboundNeedsCleaning(json), shape['needsCleaning']);
          expect(
            profileNeedsCleaning({
              'outbounds': [json],
            }),
            shape['needsCleaning'],
          );
        },
      );
    }

    test('端点里的 wireguard 是新形态，不算旧形态', () {
      expect(
        profileNeedsCleaning({
          'outbounds': <Object>[],
          'endpoints': [
            {'type': 'wireguard', 'tag': 'wg'},
          ],
        }),
        isFalse,
      );
    });

    test('订阅自带的 selector / urltest / direct 不在清单里', () {
      for (final type in ['selector', 'urltest', 'direct']) {
        expect(outboundNeedsCleaning({'type': type, 'tag': 't'}), isFalse);
      }
    });
  });
}
