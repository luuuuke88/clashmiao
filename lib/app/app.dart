import 'package:clashmiao/core/localization/locale_extensions.dart';
import 'package:clashmiao/core/localization/locale_preferences.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/app/router/app_router.dart';
import 'package:clashmiao/shared/components/system_ui.dart';
import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/theme_preferences.dart';
import 'package:clashmiao/shared/components/app_toast.dart';
import 'package:clashmiao/shared/components/modal_tokens.dart';
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

    return ToastificationWrapper(
      config: appToastConfig(context),
      child: MaterialApp.router(
        title: '喵速',
        debugShowCheckedModeBanner: false,
        locale: locale.flutterLocale,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ModalTokens.apply(theme.lightTheme()),
        darkTheme: ModalTokens.apply(theme.darkTheme()),
        themeMode: themeMode.flutterThemeMode,
        routerConfig: appRouter,
        // 系统栏：全 App 兜底样式 + edge-to-edge（见 system_ui.dart）。
        builder: (context, child) => SystemUiScope(child: child!),
      ),
    );
  }
}

/// 全局 toast 配置。入退场时长与动画是**全局默认**：没有它，任何不走
/// `AppToast` 的 toastification 调用都会回落到库默认的 600 ms。
@visibleForTesting
ToastificationConfig appToastConfig(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  final toastWidth = width > 32 ? width - 32 : width;

  return ToastificationConfig(
    itemWidth: toastWidth,
    animationDuration: AppToast.animationDuration(context),
    animationBuilder: AppToast.animationBuilder,
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
