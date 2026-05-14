import 'package:clashmiao/features/proxy/state/proxies_sort_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProxiesSortNotifier', () {
    test('默认 delay（无持久化值）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(ProxiesSortNotifier(prefs).state, ProxiesSort.delay);
    });

    test('从 prefs 读已持久化的 name 排序', () async {
      SharedPreferences.setMockInitialValues({'proxies_sort_mode': 'name'});
      final prefs = await SharedPreferences.getInstance();
      expect(ProxiesSortNotifier(prefs).state, ProxiesSort.name);
    });

    test('未知字符串 fallback 到 delay', () async {
      SharedPreferences.setMockInitialValues({'proxies_sort_mode': 'bogus'});
      final prefs = await SharedPreferences.getInstance();
      expect(ProxiesSortNotifier(prefs).state, ProxiesSort.delay);
    });

    test('updateSort 写 state + prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = ProxiesSortNotifier(prefs);
      await n.updateSort(ProxiesSort.unsorted);
      expect(n.state, ProxiesSort.unsorted);
      expect(prefs.getString('proxies_sort_mode'), 'unsorted');
    });
  });
}
