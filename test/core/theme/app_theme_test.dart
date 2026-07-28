import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = AppTheme(AppThemeMode.system, 'Shabnam');

  test('浅色主题的主色就是 logo 那个蓝，不跟随系统强调色', () {
    expect(theme.lightTheme().colorScheme.primary, BrandColors.indigo);
  });

  test('深色主题从同一颗品牌种子派生（同色系，不是系统强调色）', () {
    final primary = theme.darkTheme().colorScheme.primary;
    final brandHue = HSLColor.fromColor(BrandColors.indigo).hue;
    expect(
      (HSLColor.fromColor(primary).hue - brandHue).abs(),
      lessThan(20),
      reason: '深色下会被算法提亮，但色相必须还在品牌靛蓝附近',
    );
  });
}
