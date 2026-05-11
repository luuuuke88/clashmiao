import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kProxyModeKey = 'clashmiao_proxy_mode';

/// 当前选中的代理模式索引。默认 1 = 智能模式。
final proxyModeProvider = StateNotifierProvider<ProxyModeNotifier, int>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ProxyModeNotifier(prefs);
});

class ProxyModeNotifier extends StateNotifier<int> {
  ProxyModeNotifier(this.prefs) : super(prefs.getInt(_kProxyModeKey) ?? 1);

  final SharedPreferences prefs;

  Future<void> updateMode(int value) async {
    state = value;
    await prefs.setInt(_kProxyModeKey, value);
  }
}
