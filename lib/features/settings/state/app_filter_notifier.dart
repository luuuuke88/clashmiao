import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabledKey = 'app_filter_enabled';
const _modeKey = 'app_filter_mode';
const _listKey = 'app_filter_list';

class AppFilterState {
  const AppFilterState({
    this.enabled = false,
    this.mode = 'allow',
    this.packages = const [],
  });
  final bool enabled;
  final String mode;
  final List<String> packages;
}

class AppFilterNotifier extends StateNotifier<AppFilterState> {
  AppFilterNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static AppFilterState _load(SharedPreferences p) => AppFilterState(
    enabled: p.getBool(_enabledKey) ?? false,
    mode: p.getString(_modeKey) ?? 'allow',
    packages: p.getStringList(_listKey) ?? [],
  );

  Future<void> setEnabled(bool v) async {
    await _prefs.setBool(_enabledKey, v);
    state = AppFilterState(
      enabled: v,
      mode: state.mode,
      packages: state.packages,
    );
  }

  Future<void> setMode(String mode) async {
    await _prefs.setString(_modeKey, mode);
    state = AppFilterState(
      enabled: state.enabled,
      mode: mode,
      packages: state.packages,
    );
  }

  Future<void> togglePackage(String pkg) async {
    final list = List<String>.from(state.packages);
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    await _prefs.setStringList(_listKey, list);
    state = AppFilterState(
      enabled: state.enabled,
      mode: state.mode,
      packages: list,
    );
  }
}

final appFilterProvider =
    StateNotifierProvider<AppFilterNotifier, AppFilterState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return AppFilterNotifier(prefs);
    });
