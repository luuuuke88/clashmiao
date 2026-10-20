import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:clashmiao/domain/config/model/profile_nodes.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/subscription_payload.dart';
import 'package:clashmiao/domain/routing/data/config_parser.dart';
import 'package:clashmiao/features/config/data/backup_codec.dart';
import 'package:clashmiao/features/config/model/backup_bundle.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/temp_dirs.dart';

/// WireGuard 端点（`endpoints`）贯通 Dart 消费链路的端到端测试（spec §6.5）。
///
/// 数据是 Go 侧产出并入库的共享夹具 `kernel/testdata/shared/profiles/*.json`
/// （`flutter test` 的工作目录是包根，直接用相对路径）。四个形态：
///
/// - endpoint-only：`outbounds: []`，只有端点；
/// - mixed：出站与端点混合；
/// - endpoint-default：`§default§` 标在端点上；
/// - groups-with-endpoint：一个 selector 同时含 `auto`、一个 WireGuard 端点成员
///   和一个会被隐藏的订阅信息节点引用——专测「完整集合」与「叶子视图」的分工。
const _fixtureDir = 'kernel/testdata/shared/profiles';

String _text(String name) => File('$_fixtureDir/$name.json').readAsStringSync();

Map<String, dynamic> _cfg(String name) =>
    jsonDecode(_text(name)) as Map<String, dynamic>;

const _info = '剩余流量：100 GB';

void main() {
  const shapes = [
    'endpoint-only',
    'mixed',
    'endpoint-default',
    'groups-with-endpoint',
  ];

  test('夹具都在（路径写错不会变成空测试）', () {
    for (final name in shapes) {
      expect(
        File('$_fixtureDir/$name.json').existsSync(),
        isTrue,
        reason: name,
      );
    }
  });

  group('节点计数（叶子视图：分组不计入，端点计入）', () {
    const expected = {
      'endpoint-only': 1,
      'mixed': 3,
      'endpoint-default': 2,
      'groups-with-endpoint': 3,
    };
    for (final entry in expected.entries) {
      test('${entry.key} = ${entry.value}', () {
        expect(profileNodeCount(_cfg(entry.key)), entry.value);
        final analysis = analyzeSubscriptionPayload(_text(entry.key));
        expect(analysis.kind, SubscriptionPayloadKind.singboxJson);
        expect(analysis.nodeCount, entry.value);
        expect(analysis.looksUsable, isTrue);
      });
    }

    test('endpoint-only 的 outbounds 确实是空数组（形态没有被悄悄改过）', () {
      expect(_cfg('endpoint-only')['outbounds'], isEmpty);
    });
  });

  group('落盘：不被判空，也不被改坏', () {
    late Directory tmp;
    late ProfileRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('endpoint_shapes_');
      SharedPreferences.setMockInitialValues({});
      repo = ProfileRepository(
        dio: Dio(),
        configDir: tmp,
        prefs: await SharedPreferences.getInstance(),
        boxService: const StubBoxService(),
      );
    });

    tearDown(() async {
      await deleteTempDirBestEffort(tmp);
    });

    for (final name in shapes) {
      test('$name：直通落盘，实体一个不丢、不改，节点数不变', () async {
        expect(canPassThrough(_cfg(name)), isTrue);

        final profile = await repo.addByContent(_text(name), name: name);
        final out = jsonDecode(
          await File(repo.configFilePath(profile.id)).readAsString(),
        ) as Map<String, dynamic>;

        final input = _cfg(name);
        expect(out['endpoints'], input['endpoints'], reason: '端点原样');
        // 出站：输入的每一项原样保留；落盘只允许额外补一个 direct。
        final inputOutbounds = input['outbounds'] as List;
        final outOutbounds = out['outbounds'] as List;
        expect(outOutbounds.take(inputOutbounds.length), inputOutbounds);
        final extra = outOutbounds.skip(inputOutbounds.length).toList();
        expect(extra, [
          {'type': 'direct', 'tag': 'direct'},
        ]);
        expect(profileNodeCount(out), profileNodeCount(input));
      });
    }
  });

  group('runtimeSelectorDefaults（叶子视图）', () {
    test('endpoint-only：成员 auto + 端点，默认 auto', () {
      expect(runtimeSelectorDefaults(_cfg('endpoint-only')), {
        kRuntimeMainSelectorTag: kRuntimeAutoGroupTag,
      });
    });

    test('mixed：默认 auto', () {
      expect(runtimeSelectorDefaults(_cfg('mixed')), {
        kRuntimeMainSelectorTag: kRuntimeAutoGroupTag,
      });
    });

    test('endpoint-default：§default§ 标在端点上，默认值是该端点的真实 tag', () {
      final d = runtimeSelectorDefaults(_cfg('endpoint-default'));
      expect(d[kRuntimeMainSelectorTag], 'wg-sg§default§');
      expect(d[kRuntimeMainSelectorTag], isNot('§default§'), reason: '不是标记字面值');
    });

    test('groups-with-endpoint：订阅自带 selector 的默认值照旧，主选择组默认 auto', () {
      final d = runtimeSelectorDefaults(_cfg('groups-with-endpoint'));
      expect(d['手动选择'], '自动选择');
      expect(d[kRuntimeMainSelectorTag], kRuntimeAutoGroupTag);
    });
  });

  group('信息节点筛选（叶子视图含端点）', () {
    test('candidateLeafTags 含端点', () {
      expect(candidateLeafTags(_cfg('endpoint-only')), ['wg-hk']);
      expect(candidateLeafTags(_cfg('mixed')), ['香港01', '美国01', 'wg-jp']);
      expect(candidateLeafTags(_cfg('endpoint-default')), [
        '香港01',
        'wg-sg§default§',
      ]);
      expect(candidateLeafTags(_cfg('groups-with-endpoint')), [
        '香港01',
        _info,
        'wg-hk',
      ]);
    });

    test('信息条目排除集：只有 groups-with-endpoint 里的那一个', () {
      expect(
        subscriptionInfoExclusionsForConfig(_cfg('endpoint-only')),
        isEmpty,
      );
      expect(subscriptionInfoExclusionsForConfig(_cfg('mixed')), isEmpty);
      expect(
        subscriptionInfoExclusionsForConfig(_cfg('endpoint-default')),
        isEmpty,
      );
      expect(
        subscriptionInfoExclusionsForConfig(_cfg('groups-with-endpoint')),
        {_info},
      );
    });
  });

  group('config_parser 类型识别（完整集合）', () {
    test('groups-with-endpoint：两个分组都在，成员类型无 unknown', () {
      final groups = ConfigParser.parseConfig(_text('groups-with-endpoint'));
      expect(groups.map((g) => g.tag), ['手动选择', '自动选择']);

      final select = groups.first;
      expect(select.type, 'selector');
      expect(select.selected, '自动选择');
      expect(select.items.map((i) => i.tag), ['自动选择', '香港01', 'wg-hk', _info]);
      expect(select.items.map((i) => i.type), [
        'urltest', // auto 成员
        'shadowsocks',
        'wireguard', // 端点成员
        'shadowsocks',
      ]);

      final auto = groups.last;
      expect(auto.type, 'urltest');
      expect(auto.items.map((i) => i.type), ['shadowsocks', 'wireguard']);

      for (final g in groups) {
        expect(g.items.any((i) => i.type == 'unknown'), isFalse, reason: g.tag);
      }
    });

    test('没有分组的形态：空列表，不抛', () {
      for (final name in ['endpoint-only', 'mixed', 'endpoint-default']) {
        expect(ConfigParser.parseConfig(_text(name)), isEmpty, reason: name);
      }
    });
  });

  group('hideSubscriptionInfoOutbounds（完整集合：出站 ∪ 端点）', () {
    const hidden = '$_info $kHideNodeMarker';

    test('改名后分组成员同步更新，selector 的 default 引用同步更新', () {
      final cfg = _cfg('groups-with-endpoint');
      // 让 default 也指向信息节点，验证 default 引用被改写。
      final selector = (cfg['outbounds'] as List).first as Map;
      selector['default'] = _info;

      final renames = hideSubscriptionInfoOutbounds(cfg);
      expect(renames, {_info: hidden});

      expect(selector['outbounds'], ['自动选择', '香港01', 'wg-hk', hidden]);
      expect(selector['default'], hidden);
      final tags = [for (final e in profileEntities(cfg)) e.tag];
      expect(tags, contains(hidden));
      expect(tags, isNot(contains(_info)));
      // 端点与真实节点不动。
      expect(tags, containsAll(['香港01', 'wg-hk']));
      // 改名后：叶子视图里没有可作成员的信息节点（带隐藏标记）。
      expect(
        [
          for (final n in profileLeafNodes(cfg))
            if (!hasHideMarker(n.tag)) n.tag,
        ],
        ['香港01', 'wg-hk'],
      );
    });

    test('端点上的 detour 引用信息节点：同步更新', () {
      final cfg = _cfg('groups-with-endpoint');
      ((cfg['endpoints'] as List).single as Map)['detour'] = _info;
      hideSubscriptionInfoOutbounds(cfg);
      expect(((cfg['endpoints'] as List).single as Map)['detour'], hidden);
    });

    test('端点 tag 参与唯一性判断：改名结果撞了端点 tag，继续追加标记', () {
      final cfg = _cfg('groups-with-endpoint');
      (cfg['endpoints'] as List).add({'type': 'wireguard', 'tag': hidden});

      final renames = hideSubscriptionInfoOutbounds(cfg);

      expect(renames[_info], '$hidden$kHideNodeMarker');
      final tags = [for (final e in profileEntities(cfg)) e.tag];
      expect(tags.toSet().length, tags.length, reason: '不撞名');
    });

    test('信息条目本身是端点：同样被改名，route / dns 引用照旧更新', () {
      final cfg = <String, dynamic>{
        'outbounds': [
          {'type': 'shadowsocks', 'tag': '香港01'},
        ],
        'endpoints': [
          {'type': 'wireguard', 'tag': _info},
        ],
        'route': {
          'final': _info,
          'rules': [
            {'domain': 'example.com', 'outbound': _info},
          ],
        },
        'dns': {
          'servers': [
            {'tag': 'remote', 'detour': _info},
          ],
        },
      };
      final renames = hideSubscriptionInfoOutbounds(cfg);
      expect(renames, {_info: hidden});
      expect(((cfg['endpoints'] as List).single as Map)['tag'], hidden);
      expect((cfg['route'] as Map)['final'], hidden);
      expect(
        (((cfg['route'] as Map)['rules'] as List).single as Map)['outbound'],
        hidden,
      );
      expect(
        (((cfg['dns'] as Map)['servers'] as List).single as Map)['detour'],
        hidden,
      );
    });

    test('四个形态里没有信息节点的，一个都不改', () {
      for (final name in ['endpoint-only', 'mixed', 'endpoint-default']) {
        final cfg = _cfg(name);
        final before = jsonEncode(cfg);
        expect(hideSubscriptionInfoOutbounds(cfg), isEmpty, reason: name);
        expect(jsonEncode(cfg), before, reason: name);
      }
    });
  });

  group('备份导出 → 恢复往返通过校验', () {
    for (final name in shapes) {
      test(name, () {
        final raw = BackupCodec.encode(
          BackupBundle(
            schema: kCurrentStorageSchema,
            createdAt: 1000000,
            profiles: const [
              {'id': 'abc', 'name': 'test', 'url': 'https://example.com/sub'},
            ],
            activeProfileId: 'abc',
            profileConfigs: {'abc': _text(name)},
            preferences: const {},
            auxPreferences: const {},
          ),
        );
        var n = 0;
        final plan = BackupCodec.parse(
          raw,
          currentSchema: kCurrentStorageSchema,
          extraValidators: networkPrefValidators,
          newInc: () => 'inc${n++}',
          trusted: false,
        );
        expect(plan.configs.keys, {'abc'});
        expect(plan.needsFetch, isEmpty);
        expect(plan.configs['abc'], _text(name), reason: '配置原文原样带回');
      });
    }
  });
}
