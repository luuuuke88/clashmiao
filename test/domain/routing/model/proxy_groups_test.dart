import 'package:clashmiao/core/box_service/model/outbound.dart';
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

void main() {
  group('selectableGroupItems（线路页 / 自动测速的条目口径）', () {
    test('去掉隐藏标记节点与订阅信息条目，保留真实节点与嵌套分组，顺序不变', () {
      final items = selectableGroupItems(const [
        OutboundProxy(tag: 'auto', type: 'urltest'),
        OutboundProxy(tag: '🌐 官网地址：ncink.cc', type: 'vless'),
        OutboundProxy(tag: '🇭🇰 香港01-BGP|IEPL中继', type: 'vless'),
        OutboundProxy(tag: '剩余流量：12 GB', type: 'vless'),
        OutboundProxy(tag: 'x §hide§', type: 'vless'),
        OutboundProxy(tag: '🇸🇬 狮城01', type: 'vless'),
      ]);
      expect(items.map((i) => i.tag), [
        'auto',
        '🇭🇰 香港01-BGP|IEPL中继',
        '🇸🇬 狮城01',
      ]);
    });

    test('叶子节点全是信息条目：不排除（与运行时配置构建器同一保护）', () {
      final items = selectableGroupItems(const [
        OutboundProxy(tag: 'auto', type: 'urltest'),
        OutboundProxy(tag: '官网地址：a.cc', type: 'vless'),
      ]);
      expect(items.map((i) => i.tag), ['auto', '官网地址：a.cc']);
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
