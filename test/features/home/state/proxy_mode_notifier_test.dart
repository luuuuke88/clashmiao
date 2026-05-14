import 'package:clashmiao/features/home/state/proxy_mode_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ProxyModeNotifier', () {
    test('默认值是 1（智能）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = ProxyModeNotifier(prefs);
      expect(n.state, 1);
    });

    test('从 prefs 恢复持久化的 mode', () async {
      SharedPreferences.setMockInitialValues({'clashmiao_proxy_mode': 0});
      final prefs = await SharedPreferences.getInstance();
      final n = ProxyModeNotifier(prefs);
      expect(n.state, 0);
    });

    test('updateMode 同步更新 state + 写 prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final n = ProxyModeNotifier(prefs);
      await n.updateMode(0);
      expect(n.state, 0);
      expect(prefs.getInt('clashmiao_proxy_mode'), 0);
    });
  });
}
