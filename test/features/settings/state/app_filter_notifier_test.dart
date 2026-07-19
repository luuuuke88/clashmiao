import 'package:clashmiao/features/settings/state/app_filter_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppFilterNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'initial state has disabled filter, include mode, empty packages',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = AppFilterNotifier(prefs);
        expect(notifier.state.enabled, isFalse);
        expect(notifier.state.mode, 'include');
        expect(notifier.state.packages, isEmpty);
      },
    );

    test('setEnabled persists and updates state', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      await notifier.setEnabled(true);
      expect(notifier.state.enabled, isTrue);
      expect(prefs.getString('per_app_proxy_mode'), 'include');
    });

    test('exclude mode persists native exclude value', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      await notifier.setEnabled(true);
      await notifier.setMode('exclude');
      expect(notifier.state.mode, 'exclude');
      expect(prefs.getString('per_app_proxy_mode'), 'exclude');
    });

    test('togglePackage adds then removes package', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);

      await notifier.togglePackage('com.example.app');
      expect(notifier.state.packages, contains('com.example.app'));

      await notifier.togglePackage('com.example.app');
      expect(notifier.state.packages, isNot(contains('com.example.app')));
    });

    test('togglePackage persists to prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      await notifier.togglePackage('com.foo.bar');
      expect(
        prefs.getStringList('per_app_proxy_include_list'),
        contains('com.foo.bar'),
      );
    });

    test('loads persisted state on init', () async {
      SharedPreferences.setMockInitialValues({
        'per_app_proxy_mode': 'exclude',
        'per_app_proxy_exclude_list': ['com.example.a', 'com.example.b'],
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      expect(notifier.state.enabled, isTrue);
      expect(notifier.state.mode, 'exclude');
      expect(notifier.state.packages, hasLength(2));
    });
  });
}
