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
  });
}
