import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = AppTheme(AppThemeMode.system, 'Shabnam');

  test('浅色主题的主色是品牌靛蓝（略深一档以满足 onPrimary 4.5:1），不跟随系统强调色', () {
    final scheme = theme.lightTheme().colorScheme;
    expect(scheme.primary, BrandColors.indigoOnLight);
    expect(scheme.onPrimary, Colors.white);
    // 色相仍与 logo 的靛蓝一致。
    expect(
      (HSLColor.fromColor(scheme.primary).hue -
              HSLColor.fromColor(BrandColors.indigo).hue)
          .abs(),
      lessThan(5),
    );
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
