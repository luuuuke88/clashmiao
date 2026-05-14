import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'locale_preferences.g.dart';

@Riverpod(keepAlive: true)
class LocalePreferences extends _$LocalePreferences {
  @override
  AppLocale build() {
    final persisted = ref
        .watch(sharedPreferencesProvider)
        .requireValue
        .getString("locale");
    if (persisted == null) return AppLocaleUtils.findDeviceLocale();
    if (persisted == "zh") {
      return AppLocale.zhCn;
    }
    try {
      return AppLocale.values.byName(persisted);
    } catch (e) {
      return AppLocale.en;
    }
  }

  Future<void> changeLocale(AppLocale value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .setString("locale", value.name);
  }
}
