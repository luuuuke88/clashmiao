import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/domain/config/model/subscription_info_node.dart';
import 'package:clashmiao/domain/routing/model/proxy_groups.dart';
import 'package:flutter_test/flutter_test.dart';

const _hk = OutboundProxy(tag: '香港01', type: 'vless');
const _sg = OutboundProxy(tag: '狮城01', type: 'vless');
const _auto = OutboundProxy(tag: 'auto', type: 'urltest');

/// 运行时形态：内核重建的主选择组 + 自动选择组（订阅自带的分组被丢掉）。
const _runtime = [
  OutboundGroup(
    tag: 'select',
    type: 'selector',
    selected: 'auto',
    items: [_auto, _hk, _sg],
  ),
  OutboundGroup(
    tag: 'auto',
    type: 'urltest',
    selected: '香港01',
    items: [_hk, _sg],
  ),
];

/// 按这些分组拼成的配置（全部叶子节点）算排除集——与线路页同一个函数。
Set<String> subscriptionInfoExclusions(List<OutboundGroup> groups) =>
    subscriptionInfoExclusionsForConfig({
      'outbounds': [
        for (final g in groups)
          for (final item in g.items) {'tag': item.tag, 'type': item.type},
      ],
    });

void main() {
  group('primaryVisibleGroup', () {
    test('只有隐藏条目的分组不当主组：与线路页展示的主组一致', () {
      const infoOnly = OutboundGroup(
        tag: 'info',
        type: 'selector',
        selected: '官网 §hide§',
        items: [OutboundProxy(tag: '官网 §hide§', type: 'vless')],
      );
      const real = OutboundGroup(
        tag: 'real',
        type: 'selector',
        selected: 'hk',
        items: [OutboundProxy(tag: 'hk', type: 'vless')],
      );
      expect(primaryVisibleGroup([infoOnly, real])?.tag, 'real');
      expect(primaryVisibleGroup([infoOnly])?.tag, 'info');
    });
  });

  group('primaryDisplayGroup', () {
    const empty = OutboundGroup(
      tag: 'info',
      type: 'selector',
      selected: '',
      items: [],
    );
    const real = OutboundGroup(
      tag: 'real',
      type: 'selector',
      selected: 'hk',
      items: [OutboundProxy(tag: 'hk', type: 'vless')],
    );
    test('跳过排除后为空的分组', () {
      expect(primaryDisplayGroup([empty, real])?.tag, 'real');
    });
    test('都为空时退回第一个；没有分组为 null', () {
      expect(primaryDisplayGroup([empty])?.tag, 'info');
      expect(primaryDisplayGroup(const []), isNull);
    });
  });

  group('信息条目排除（线路页 / 自动测速的条目口径）', () {
    test('去掉隐藏标记节点与订阅信息条目，保留真实节点（含关键词的）与嵌套分组，顺序不变', () {
      const items = [
        OutboundProxy(tag: 'auto', type: 'urltest'),
        OutboundProxy(tag: '🌐 官网地址：ncink.cc', type: 'vless'),
        OutboundProxy(tag: '🇭🇰 香港01-BGP|IEPL中继', type: 'vless'),
        OutboundProxy(tag: '剩余流量：12 GB', type: 'vless'),
        OutboundProxy(tag: 'x §hide§', type: 'vless'),
        OutboundProxy(tag: '香港01 官网优化 IEPL', type: 'vless'),
        OutboundProxy(tag: 'HK Official IEPL 01', type: 'vless'),
      ];
      const group = OutboundGroup(
        tag: 'select',
        type: 'selector',
        selected: 'auto',
        items: items,
      );
      final out = selectableGroupItems(
        items,
        subscriptionInfoExclusions([group]),
      );
      expect(out.map((i) => i.tag), [
        'auto',
        '🇭🇰 香港01-BGP|IEPL中继',
        '香港01 官网优化 IEPL',
        'HK Official IEPL 01',
      ]);
    });

    test('只有信息条目的分组与真实节点分组并存：按整份订阅判断，信息组同样被清空', () {
      const infoOnly = OutboundGroup(
        tag: '订阅信息',
        type: 'selector',
        selected: '官网地址：a.cc',
        items: [
          OutboundProxy(tag: '官网地址：a.cc', type: 'vless'),
          OutboundProxy(tag: '剩余流量：1 GB', type: 'vless'),
        ],
      );
      const real = OutboundGroup(
        tag: '节点',
        type: 'selector',
        selected: 'hk',
        items: [OutboundProxy(tag: 'hk', type: 'vless')],
      );
      final exclusions = subscriptionInfoExclusions([infoOnly, real]);
      expect(selectableGroupItems(infoOnly.items, exclusions), isEmpty);
      expect(selectableGroupItems(real.items, exclusions).map((i) => i.tag), [
        'hk',
      ]);
    });

    test('整份订阅全是信息条目：不排除（与运行时配置构建器同一保护）', () {
      const group = OutboundGroup(
        tag: 'select',
        type: 'selector',
        selected: 'auto',
        items: [
          OutboundProxy(tag: 'auto', type: 'urltest'),
          OutboundProxy(tag: '官网地址：a.cc', type: 'vless'),
        ],
      );
      final out = selectableGroupItems(
        group.items,
        subscriptionInfoExclusions([group]),
      );
      expect(out.map((i) => i.tag), ['auto', '官网地址：a.cc']);
    });
  });

  group('applyStoredSelections（离线展示叠加手选）', () {
    test('有记录且节点在组内：以记录为选中项', () {
      final out = applyStoredSelections(_runtime, {'select': '狮城01'});
      expect(out.first.selected, '狮城01');
      expect(out.last.selected, '香港01', reason: '没有记录的组不动');
    });

    test('记录的节点不在组内 / 没有记录：保持原样', () {
      expect(
        applyStoredSelections(_runtime, {'select': '不存在'}).first.selected,
        'auto',
      );
      expect(
        identical(applyStoredSelections(_runtime, const {}), _runtime),
        isTrue,
      );
    });
  });

  // 真机验收 BUG-1：旧版本按配置文件里的分组 tag（`proxy`）记下的手选，在运行时
  // 根本不存在，每次重放都 selector not found。迁移计划：先写目标、确认后删来源。
  group('planSelectionMigration（手选存储与运行时分组对齐）', () {
    final tags = {'select', 'auto'};
    final primary = _runtime.first;

    SelectionMigration plan(Map<String, String> stored) =>
        planSelectionMigration(stored, tags, primary);

    test('运行时不存在的组：节点迁到主选择组', () {
      final p = plan({'proxy': '香港01'});
      expect(p.adopt, {'proxy': (target: 'select', node: '香港01')});
      expect(p.superseded, isEmpty);
      expect(p.orphaned, isEmpty);
    });

    test('主选择组已有记录：来源被取代（目标确认后删），不覆盖目标', () {
      final p = plan({'proxy': '香港01', 'select': '狮城01'});
      expect(p.adopt, isEmpty);
      expect(p.superseded, {'proxy': 'select'});
    });

    test('多个旧来源指向同一主组：只采纳一个，其余被取代', () {
      final p = plan({'a-old': '香港01', 'b-old': '狮城01'});
      expect(p.adopt, {'a-old': (target: 'select', node: '香港01')});
      expect(p.superseded, {'b-old': 'select'});
    });

    test('旧记录的节点不在主组里：保留（orphaned），不删', () {
      final p = plan({'proxy': '已下线节点'});
      expect(p.adopt, isEmpty);
      expect(p.superseded, isEmpty);
      expect(p.orphaned, {'proxy'});
    });

    test('主组不是选择器：无从迁移，保留', () {
      final p = planSelectionMigration(
        {'proxy': '香港01'},
        {'auto'},
        _runtime.last,
      );
      expect(p.orphaned, {'proxy'});
    });

    test('记录都在运行时里 / 还没有运行时分组：什么都不做', () {
      expect(plan({'select': '香港01'}).isEmpty, isTrue);
      expect(
        planSelectionMigration({'proxy': '香港01'}, const {}, null).isEmpty,
        isTrue,
      );
    });
  });
}
