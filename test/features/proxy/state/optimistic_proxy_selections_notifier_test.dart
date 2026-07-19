import 'package:clashmiao/features/proxy/state/optimistic_proxy_selections_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OptimisticProxySelectionsNotifier', () {
    test('初始为空 map', () {
      expect(OptimisticProxySelectionsNotifier().state, isEmpty);
    });

    test('update 写入新 group → proxy', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('Proxy', 'node-a');
      expect(n.state, {'Proxy': 'node-a'});
    });

    test('update 同 group 覆盖旧值', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('Proxy', 'node-a');
      n.update('Proxy', 'node-b');
      expect(n.state, {'Proxy': 'node-b'});
    });

    test('update 不同 group 合并保留', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('GroupA', 'a1');
      n.update('GroupB', 'b1');
      expect(n.state, {'GroupA': 'a1', 'GroupB': 'b1'});
    });

    test('revert：previousProxy 为 null 时移除该 group 条目', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('Proxy', 'node-a');
      n.revert('Proxy', null);
      expect(n.state, isEmpty);
    });

    test('revert：previousProxy 非空时恢复为该旧值', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('Proxy', 'node-a'); // 模拟之前已经乐观切换成功过一次
      n.update('Proxy', 'node-b'); // 用户点了新节点，乐观更新覆盖旧值
      n.revert('Proxy', 'node-a'); // node-b 切换失败，回滚到 node-a
      expect(n.state, {'Proxy': 'node-a'});
    });

    test('revert 只影响目标 group，不影响其他 group', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('GroupA', 'a1');
      n.update('GroupB', 'b1');
      n.revert('GroupA', null);
      expect(n.state, {'GroupB': 'b1'});
    });

    test('revert：previousProxy 为 null 且 group 本不存在时是安全的 no-op', () {
      final n = OptimisticProxySelectionsNotifier();
      n.update('GroupB', 'b1');
      n.revert('GroupA', null);
      expect(n.state, {'GroupB': 'b1'});
    });
  });
}
