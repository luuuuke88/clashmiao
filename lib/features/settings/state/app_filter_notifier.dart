import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化 key 必须跟 Android 侧 `PrefsKey.APP_FILTER_*` 对齐
/// （native 读 `flutter.per_app_proxy_*`，shared_preferences 写盘时自动加
/// `flutter.` 前缀）。TunnelService 建 TUN 时按 mode 读对应名单决定
/// addAllowedApplication / addDisallowedApplication。
const _modeKey = 'per_app_proxy_mode'; // off | include | exclude
const _includeListKey = 'per_app_proxy_include_list';
const _excludeListKey = 'per_app_proxy_exclude_list';

class AppFilterState {
  const AppFilterState({
    this.enabled = false,
    this.mode = 'allow',
    this.packages = const [],
  });

  final bool enabled;

  /// UI 语义：'allow' = 仅勾选的应用走代理，'exclude' = 勾选的应用绕过代理。
  final String mode;
  final List<String> packages;
}

class AppFilterNotifier extends StateNotifier<AppFilterState> {
  AppFilterNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static AppFilterState _load(SharedPreferences p) {
    final nativeMode = p.getString(_modeKey) ?? 'off';
    final enabled = nativeMode != 'off';
    final uiMode = nativeMode == 'exclude' ? 'exclude' : 'allow';
    final listKey = uiMode == 'exclude' ? _excludeListKey : _includeListKey;
    return AppFilterState(
      enabled: enabled,
      mode: uiMode,
      packages: p.getStringList(listKey) ?? [],
    );
  }

  /// 把当前 UI 状态写盘成 native 协议：mode=off 表示禁用；
  /// 启用时按 UI mode 映射 include/exclude，名单写到对应 key。
  Future<void> _persist(AppFilterState s) async {
    final nativeMode = !s.enabled
        ? 'off'
        : (s.mode == 'exclude' ? 'exclude' : 'include');
    await _prefs.setString(_modeKey, nativeMode);
    final listKey = s.mode == 'exclude' ? _excludeListKey : _includeListKey;
    await _prefs.setStringList(listKey, s.packages);
    state = s;
  }

  Future<void> setEnabled(bool v) => _persist(
    AppFilterState(enabled: v, mode: state.mode, packages: state.packages),
  );

  Future<void> setMode(String mode) async {
    // include / exclude 两份名单独立存：切换语义时沿用同一份勾选会让已选
    // 应用的行为瞬间反转，改为读回该模式各自上次保存的名单。
    final listKey = mode == 'exclude' ? _excludeListKey : _includeListKey;
    await _persist(
      AppFilterState(
        enabled: state.enabled,
        mode: mode,
        packages: _prefs.getStringList(listKey) ?? [],
      ),
    );
  }

  Future<void> togglePackage(String pkg) {
    final list = List<String>.from(state.packages);
    if (list.contains(pkg)) {
      list.remove(pkg);
    } else {
      list.add(pkg);
    }
    return _persist(
      AppFilterState(enabled: state.enabled, mode: state.mode, packages: list),
    );
  }
}

final appFilterProvider =
    StateNotifierProvider<AppFilterNotifier, AppFilterState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider).requireValue;
      return AppFilterNotifier(prefs);
    });
