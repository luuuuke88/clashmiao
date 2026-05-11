import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:clashmiao/core/localization/gen/translations.g.dart';

part 'translations.g.dart';

@Riverpod(keepAlive: true)
Translations translations(TranslationsRef ref) =>
    ref.watch(localePreferencesProvider).build();
