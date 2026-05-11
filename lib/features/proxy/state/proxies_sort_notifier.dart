import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kProxiesSortKey = 'proxies_sort_mode';

enum ProxiesSort {
  unsorted,
  name,
  delay;

  String present(TranslationsEn t) => switch (this) {
        ProxiesSort.unsorted => t.proxies.sortOptions.unsorted,
        ProxiesSort.name => t.proxies.sortOptions.name,
        ProxiesSort.delay => t.proxies.sortOptions.delay,
      };
}

final proxiesSortProvider =
    StateNotifierProvider<ProxiesSortNotifier, ProxiesSort>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return ProxiesSortNotifier(prefs);
});

class ProxiesSortNotifier extends StateNotifier<ProxiesSort> {
  ProxiesSortNotifier(this.prefs) : super(_read(prefs));

  final SharedPreferences prefs;

  static ProxiesSort _read(SharedPreferences prefs) {
    final name = prefs.getString(_kProxiesSortKey);
    return ProxiesSort.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ProxiesSort.delay,
    );
  }

  Future<void> updateSort(ProxiesSort value) async {
    state = value;
    await prefs.setString(_kProxiesSortKey, value.name);
  }
}
