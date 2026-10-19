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
  // 根本不存在，每次重放都 selector not found。
  group('planSelectionMigration（手选存储与运行时分组对齐）', () {
    test('运行时不存在的组：节点迁到主选择组，旧记录删除', () {
      final plan = planSelectionMigration({'proxy': '香港01'}, _runtime);
      expect(plan.adopt, {'select': '香港01'});
      expect(plan.drop, {'proxy'});
    });

    test('主选择组已有记录：不覆盖，只删旧记录', () {
      final plan = planSelectionMigration({
        'proxy': '香港01',
        'select': '狮城01',
      }, _runtime);
      expect(plan.adopt, isEmpty);
      expect(plan.drop, {'proxy'});
    });

    test('旧记录的节点不在主组里：不迁移，只删除', () {
      final plan = planSelectionMigration({'proxy': '已下线节点'}, _runtime);
      expect(plan.adopt, isEmpty);
      expect(plan.drop, {'proxy'});
    });

    test('记录都在运行时里：什么都不做', () {
      final plan = planSelectionMigration({'select': '香港01'}, _runtime);
      expect(plan.adopt, isEmpty);
      expect(plan.drop, isEmpty);
    });

    test('还没有实时分组：不做判断', () {
      final plan = planSelectionMigration({'proxy': '香港01'}, const []);
      expect(plan.adopt, isEmpty);
      expect(plan.drop, isEmpty);
    });
  });
}
