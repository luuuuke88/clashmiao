import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:clashmiao/core/localization/gen/translations.g.dart';

/// 当前语言的翻译表，随 [localePreferencesProvider] 切换。常驻（不自动释放）。
final translationsProvider = Provider<Translations>(
  (ref) => ref.watch(localePreferencesProvider).buildSync(),
  name: 'translationsProvider',
);
