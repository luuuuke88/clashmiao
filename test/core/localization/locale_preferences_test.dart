import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
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
  group('LocalePreferences', () {
    test('从 prefs 恢复持久化 locale', () async {
      final c = await _container({'locale': 'en'});
      expect(c.read(localePreferencesProvider), AppLocale.en);
    });

    test('legacy "zh" 映射到 zhCn', () async {
      final c = await _container({'locale': 'zh'});
      expect(c.read(localePreferencesProvider), AppLocale.zhCn);
    });

    test('未知 locale 字符串 fallback 到 en', () async {
      final c = await _container({'locale': 'klingon'});
      expect(c.read(localePreferencesProvider), AppLocale.en);
    });

    test('changeLocale 更新 + 持久化', () async {
      final c = await _container({});
      await c
          .read(localePreferencesProvider.notifier)
          .changeLocale(AppLocale.fa);
      expect(c.read(localePreferencesProvider), AppLocale.fa);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale'), 'fa');
    });
  });
}
