import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_preferences.g.dart';

@Riverpod(keepAlive: true)
class ThemePreferences extends _$ThemePreferences {
  @override
  AppThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    // 未知枚举值（版本回退、手改）或错误类型：回落默认，不能在启动时抛出。
    final Object? persisted;
    try {
      persisted = prefs.get("theme_mode");
    } catch (_) {
      return AppThemeMode.system;
    }
    if (persisted is! String) return AppThemeMode.system;
    return AppThemeMode.values.asNameMap()[persisted] ?? AppThemeMode.system;
  }

  Future<void> changeThemeMode(AppThemeMode value) async {
    state = value;
    await ref
        .read(sharedPreferencesProvider)
        .requireValue
        .setString("theme_mode", value.name);
  }
}
