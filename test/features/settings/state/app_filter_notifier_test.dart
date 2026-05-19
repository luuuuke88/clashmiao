import 'package:clashmiao/features/settings/state/app_filter_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppFilterNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'initial state has disabled filter, allow mode, empty packages',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final notifier = AppFilterNotifier(prefs);
        expect(notifier.state.enabled, isFalse);
        expect(notifier.state.mode, 'allow');
        expect(notifier.state.packages, isEmpty);
      },
    );

    test('setEnabled persists and updates state', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      await notifier.setEnabled(true);
      expect(notifier.state.enabled, isTrue);
      expect(prefs.getBool('app_filter_enabled'), isTrue);
    });

    test('setMode persists and updates state', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      await notifier.setMode('block');
      expect(notifier.state.mode, 'block');
      expect(prefs.getString('app_filter_mode'), 'block');
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
      expect(prefs.getStringList('app_filter_list'), contains('com.foo.bar'));
    });

    test('loads persisted state on init', () async {
      SharedPreferences.setMockInitialValues({
        'app_filter_enabled': true,
        'app_filter_mode': 'block',
        'app_filter_list': ['com.example.a', 'com.example.b'],
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = AppFilterNotifier(prefs);
      expect(notifier.state.enabled, isTrue);
      expect(notifier.state.mode, 'block');
      expect(notifier.state.packages, hasLength(2));
    });
  });
}
