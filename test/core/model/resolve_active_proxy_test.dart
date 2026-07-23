import 'package:clashmiao/core/model/outbound.dart';
import 'package:flutter_test/flutter_test.dart';

/// 覆盖 `resolveActiveProxy`——首页"当前生效节点"解析。真机（Pixel 4 XL，
/// clash-verge VLESS+Reality 订阅）实测发现：连接明明成功、线路页能正确显示
/// `JP-Reality-Stable`，但首页节点名却是"未知"。根因是首页此前直接取
/// `groups.first.selected`，而核心推送的分组第一条并非用户主线路。
void main() {
  OutboundProxy leaf(String tag, {int delay = 0}) =>
      OutboundProxy(tag: tag, type: 'vless', delay: delay);

  group('resolveActiveProxy', () {
    test('主选择器 proxy 选中叶子节点 → 返回该节点（含延迟）', () {
      final groups = [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'JP-Reality-Stable',
          items: [leaf('JP-Reality-Stable', delay: 123)],
        ),
      ];
      final active = resolveActiveProxy(groups);
      expect(active?.tag, 'JP-Reality-Stable');
      expect(active?.delay, 123);
    });

    test('第一条是 GLOBAL 伪分组时跳过，取 proxy 主组的节点（回归真机"未知"）', () {
      final groups = [
        // 核心常把 GLOBAL 排在最前，其 selected 指向另一个分组名而非叶子。
        OutboundGroup(
          tag: 'GLOBAL',
          type: 'selector',
          selected: 'proxy',
          items: [leaf('proxy'), leaf('direct')],
        ),
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'JP-Reality-Stable',
          items: [leaf('JP-Reality-Stable', delay: 88)],
        ),
      ];
      final active = resolveActiveProxy(groups);
      expect(
        active?.tag,
        'JP-Reality-Stable',
        reason: '不能显示 GLOBAL 的 selected(proxy)，要下钻到真实叶子',
      );
      expect(active?.delay, 88);
    });

    test('嵌套 selector：proxy→select→叶子，一路下钻到叶子节点', () {
      final groups = [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'select',
          items: [leaf('select')],
        ),
        OutboundGroup(
          tag: 'select',
          type: 'selector',
          selected: 'JP-Reality-Stable',
          items: [leaf('JP-Reality-Stable', delay: 55)],
        ),
      ];
      final active = resolveActiveProxy(groups);
      expect(active?.tag, 'JP-Reality-Stable');
      expect(active?.delay, 55);
    });

    test('selected 不在 items 里时回退到第一个 item，不返回 null（好过"未知"）', () {
      final groups = [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'ghost-node',
          items: [leaf('JP-Reality-Stable', delay: 7)],
        ),
      ];
      final active = resolveActiveProxy(groups);
      expect(active?.tag, 'JP-Reality-Stable');
    });

    test('只有 GLOBAL/DIRECT/REJECT 伪分组 → 返回 null', () {
      final groups = [
        const OutboundGroup(
          tag: 'DIRECT',
          type: 'direct',
          selected: '',
          items: [],
        ),
        const OutboundGroup(
          tag: 'REJECT',
          type: 'block',
          selected: '',
          items: [],
        ),
      ];
      expect(resolveActiveProxy(groups), isNull);
    });

    test('空分组列表 → 返回 null', () {
      expect(resolveActiveProxy(const []), isNull);
    });

    test('成环的嵌套 selector 不死循环（深度上限兜底）', () {
      final groups = [
        OutboundGroup(
          tag: 'proxy',
          type: 'selector',
          selected: 'select',
          items: [leaf('select')],
        ),
        OutboundGroup(
          tag: 'select',
          type: 'selector',
          selected: 'proxy',
          items: [leaf('proxy')],
        ),
      ];
      // 不校验具体返回值，只要求不抛异常 / 不挂死。
      expect(() => resolveActiveProxy(groups), returnsNormally);
    });
  });
}
