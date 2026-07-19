import 'package:clashmiao/core/localization/locale_extensions.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/router/app_router.dart';
import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

class ClashMiaoApp extends ConsumerWidget {
  const ClashMiaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final theme = AppTheme(themeMode, locale.preferredFontFamily);
    // this handles setting the translation locale automatically based on provider
    ref.watch(translationsProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return ToastificationWrapper(
          config: _appToastConfig(context),
          child: MaterialApp.router(
            title: '喵速',
            debugShowCheckedModeBanner: false,
            locale: locale.flutterLocale,
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme.lightTheme(lightDynamic),
            darkTheme: theme.darkTheme(darkDynamic),
            themeMode: themeMode.flutterThemeMode,
            routerConfig: appRouter,
          ),
        );
      },
    );
  }
}

ToastificationConfig _appToastConfig(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  final toastWidth = width > 32 ? width - 32 : width;

  return ToastificationConfig(
    itemWidth: toastWidth,
    marginBuilder: (context, alignment) {
      final y = alignment.resolve(Directionality.of(context)).y;
      if (y >= 0.5) {
        final safeBottom = MediaQuery.of(context).padding.bottom;
        // 把 toast 放在底部导航条上方，但不要抬到屏幕中部。
        return EdgeInsets.only(left: 16, right: 16, bottom: safeBottom + 88);
      }
      if (y <= -0.5) {
        return const EdgeInsets.only(top: 12);
      }
      return EdgeInsets.zero;
    },
    applyMediaQueryViewInsets: true,
  );
}
