import 'package:flutter/material.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme(ColorScheme? lightColorScheme) {
    final ColorScheme scheme = lightColorScheme ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6), // Vibrant Blue
          brightness: Brightness.light,
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
        titleLarge: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
      ),
      fontFamily: fontFamily,
      extensions: <ThemeExtension<dynamic>>{
        ConnectionButtonTheme.light,
        AiUiTheme.light,
      },
    );
  }

  ThemeData darkTheme(ColorScheme? darkColorScheme) {
    final ColorScheme scheme = darkColorScheme ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366f1), // UI Primary
          brightness: Brightness.dark,
          surface: const Color(0xFF16161a), // Card Dark
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.black, // Pure Black
      fontFamily: fontFamily,
      extensions: <ThemeExtension<dynamic>>{
        ConnectionButtonTheme.light,
        AiUiTheme.dark,
      },
    );
  }
}
