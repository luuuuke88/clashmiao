import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await c.read(sharedPreferencesProvider.future);
  return c;
}

void main() {
  group('ThemePreferences', () {
    test('默认 system（无持久化值）', () async {
      final c = await _container({});
      expect(c.read(themePreferencesProvider), AppThemeMode.system);
    });

    test('从 prefs 恢复 dark', () async {
      final c = await _container({'theme_mode': 'dark'});
      expect(c.read(themePreferencesProvider), AppThemeMode.dark);
    });

    test('changeThemeMode 更新 state + prefs', () async {
      final c = await _container({});
      await c
          .read(themePreferencesProvider.notifier)
          .changeThemeMode(AppThemeMode.light);
      expect(c.read(themePreferencesProvider), AppThemeMode.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'light');
    });
  });
}
