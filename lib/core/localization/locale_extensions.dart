import 'dart:io';
import 'package:clashmiao/core/localization/gen/translations.g.dart';

extension AppLocaleX on AppLocale {
  String get preferredFontFamily => this == AppLocale.fa ? "Shabnam" : (Platform.isIOS || Platform.isMacOS ? "" : "Emoji");
  String get localeName => switch (flutterLocale.toString()) {
        "en" => "English",
        "fa" => "فارسی",
        "ar" => "العربية",
        "ru" => "Русский",
        "zh" || "zh_CN" => "中文 (中国)",
        "zh_TW" => "中文 (台湾)",
        "tr" => "Türkçe",
        "es" => "Spanish",
        "id" => "Indonesian",
        "pt_BR" => "Portuguese (Brazil)",
        _ => "Unknown",
      };
}
