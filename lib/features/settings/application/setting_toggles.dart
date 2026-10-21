import 'package:clashmiao/core/env/build_config.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页里按「键 + 默认值」读写布尔偏好的开关 provider family。
///
/// 从设置页私有声明提取到这里，是为了备份恢复后能统一失效它
/// （`ref.invalidate(boolPreferenceProvider)` 会让整个 family 重读偏好）。
final boolPreferenceProvider = StateNotifierProvider.autoDispose
    .family<BoolPreferenceNotifier, bool, ({bool defaultValue, String key})>((
      ref,
      spec,
    ) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return BoolPreferenceNotifier(prefs, spec.key, spec.defaultValue);
    });

class BoolPreferenceNotifier extends StateNotifier<bool> {
  BoolPreferenceNotifier(this._prefs, this._key, bool defaultValue)
    : super(_prefs.getBool(_key) ?? defaultValue);

  final SharedPreferences _prefs;
  final String _key;

  Future<void> update(bool value) async {
    state = value;
    await _prefs.setBool(_key, value);
  }
}

/// 这个构建有没有编进崩溃 / 性能上报（见 [hasCrashReporting]）。没有时设置页
/// 不显示「数据分析」开关。做成 provider 是为了测试能覆盖。
final crashReportingAvailableProvider = Provider<bool>(
  (ref) => hasCrashReporting,
);
