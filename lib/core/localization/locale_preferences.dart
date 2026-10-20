import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 界面语言偏好。常驻（不自动释放）：整个 App 生命周期都要读它。
final localePreferencesProvider =
    NotifierProvider<LocalePreferences, AppLocale>(
      LocalePreferences.new,
      name: 'localePreferencesProvider',
    );

class LocalePreferences extends Notifier<AppLocale> {
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
