import 'package:flutter/material.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';

/// 主题一律从品牌靛蓝派生，不跟随系统强调色。
///
/// 之前用 `dynamic_color` 把系统强调色喂进来，结果是每台机器的"主色"都不一样：
/// 选中态、连接按钮、强调图标全都变成用户桌面的颜色，跟 App 图标那只蓝猫对不
/// 上。品牌色是产品的一部分，不该由桌面设置决定。
class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.indigo,
      brightness: Brightness.light,
      primary: BrandColors.indigo,
      surface: Colors.white,
      onSurface: const Color(0xFF1E293B), // Slate 800
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF1E293B)),
        bodyMedium: TextStyle(color: Color(0xFF475569)), // Slate 600
        titleLarge: TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.bold,
        ),
      ),
      fontFamily: fontFamily,
      switchTheme: _switchTheme(isLight: true),
      extensions: <ThemeExtension<dynamic>>{
        ConnectionButtonTheme.light,
        AiUiTheme.light,
      },
    );
  }

  ThemeData darkTheme() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: BrandColors.indigo,
      brightness: Brightness.dark,
      surface: const Color(0xFF16161a), // Card Dark
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black, // Pure Black
      fontFamily: fontFamily,
      switchTheme: _switchTheme(isLight: false),
      extensions: <ThemeExtension<dynamic>>{
        ConnectionButtonTheme.light,
        AiUiTheme.dark,
      },
    );
  }

  /// 开关的统一外观。
  ///
  /// Material 3 默认的关闭态是"深色小圆点 + 一圈粗描边"，在设置列表里几个开关
  /// 排在一起时那圈描边格外扎眼，像没做完的占位控件。这里改成 iOS 那套读法：
  /// 轨道承担全部语义（灰＝关、品牌靛蓝＝开），滑块恒为白色，描边去掉。
  static SwitchThemeData _switchTheme({required bool isLight}) {
    final offTrack = isLight
        ? const Color(0xFFCBD5E1) // Slate 300：白滑块压上去要能看清
        : const Color(0x33FFFFFF);

    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return isLight ? const Color(0xFFF8FAFC) : const Color(0x61FFFFFF);
        }
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final on = states.contains(WidgetState.selected);
        final track = on ? BrandColors.indigo : offTrack;
        if (states.contains(WidgetState.disabled)) {
          return track.withValues(alpha: 0.38);
        }
        return track;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
    );
  }
}
