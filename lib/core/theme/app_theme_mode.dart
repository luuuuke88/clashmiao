import 'package:flutter/material.dart';
import 'package:clashmiao/core/localization/translations.dart';

enum AppThemeMode {
  system,
  light,
  dark;

  String present(TranslationsEn t) => switch (this) {
        system => t.settings.general.themeModes.system,
        light => t.settings.general.themeModes.light,
        dark => t.settings.general.themeModes.dark,
      };

  ThemeMode get flutterThemeMode => switch (this) {
        system => ThemeMode.system,
        light => ThemeMode.light,
        dark => ThemeMode.dark,
      };

  bool get trueBlack => false;
}
