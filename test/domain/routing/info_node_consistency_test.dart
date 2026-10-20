import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/domain/config/data/runtime_config_builder.dart';
import 'package:clashmiao/domain/routing/data/config_parser.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/temp_dirs.dart';

/// 按内核配置构建器的口径算主选择组 / 自动选择组的节点成员（跳过非节点类型与
/// 带隐藏标记的出站）。
List<String> _kernelMembers(Map<String, dynamic> cfg) => [
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

// 同一份订阅：构建器决定的运行时成员，与线路页对离线分组（直接解析订阅配置）
// 展示的节点，必须是同一组——信息条目两边都没有，含关键词的真实节点两边都有。
void main() {
  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('info_consistency_');
  });
  tearDown(() => deleteTempDirBestEffort(tmp));

  const realNodes = [
    '🇭🇰 香港01-BGP|IEPL中继',
    '香港01 官网优化 IEPL',
    'HK Official IEPL 01',
    'HK Traffic IEPL 02',
    'JP Reset 03',
  ];
  const infoNodes = ['🌐 官网地址：ncink.cc', '剩余流量：123.4 GB', '套餐到期：2026-12-01'];

  final subscription = {
    'outbounds': [
      {'type': 'selector', 'tag': '订阅信息', 'outbounds': infoNodes},
      {
        'type': 'selector',
        'tag': '节点选择',
        'outbounds': ['自动选择', ...realNodes],
      },
      {'type': 'urltest', 'tag': '自动选择', 'outbounds': realNodes},
      for (final tag in [...infoNodes, ...realNodes])
        {'type': 'vless', 'tag': tag, 'server': 'a.example', 'server_port': 1},
      {'type': 'direct', 'tag': 'direct'},
    ],
  };

  test('构建器成员 == 线路页可见节点：信息条目两边都没有，含关键词的真实节点两边都有', () async {
    final raw = jsonEncode(subscription);
    final profile = File('${tmp.path}/profile.json')..writeAsStringSync(raw);
    final built = await RuntimeConfigBuilder().build(
      baseProfile: profile,
      workingDir: tmp,
    );
    final cfg = jsonDecode(await built.readAsString()) as Map<String, dynamic>;
    final members = _kernelMembers(cfg);
    expect(members, realNodes);

    final groups = ConfigParser.parseConfig(raw);
    final exclusions = subscriptionInfoExclusions(groups);
    final visibleByGroup = {
      for (final g in groups)
        g.tag: [
          for (final item in selectableGroupItems(g.items, exclusions))
            if (!isGroupProxyType(item.type)) item.tag,
        ],
    };
    expect(visibleByGroup['订阅信息'], isEmpty, reason: '信息专用组整组隐藏');
    expect(visibleByGroup['节点选择'], realNodes);
    expect(visibleByGroup['自动选择'], realNodes);
    final allVisible = {for (final v in visibleByGroup.values) ...v};
    expect(allVisible, members.toSet());
  });
}
