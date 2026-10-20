import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x 对比度：(L1 + 0.05) / (L2 + 0.05)，L 为相对亮度。
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 一组「状态色小字真实会压在上面」的表面。全部由主题与组件里的真实常量
/// 叠出来，不是手写的近似色：
/// - 页底（`scaffoldBackgroundColor`）以及叠了品牌晕染最浓处（靛蓝 + 金）的页底；
/// - 卡片（GlassCard：白 72% / 深色 #1C1C22 62%）压在上面；
/// - 代理页选中行：卡片上再叠 8% primary；
/// - 首页节点胶囊 / 分段槽的凹槽底（`softBackgroundColor`）压在卡片上。
Map<String, Color> _surfaces(Brightness brightness) {
  final light = brightness == Brightness.light;
  final theme = AppTheme(AppThemeMode.system, 'x');
  final data = light ? theme.lightTheme() : theme.darkTheme();
  final aiUi = light ? AiUiTheme.light : AiUiTheme.dark;
  final scaffold = data.scaffoldBackgroundColor;
  final indigoAlpha = light ? 0.16 : 0.22;
  final goldAlpha = light ? 0.14 : 0.07;
  final washed = Color.alphaBlend(
    BrandColors.gold.withValues(alpha: goldAlpha),
    Color.alphaBlend(
      BrandColors.indigo.withValues(alpha: indigoAlpha),
      scaffold,
    ),
  );
  final cardPaint = light
      ? Colors.white.withValues(alpha: 0.72)
      : const Color(0xFF1C1C22).withValues(alpha: 0.62);
  final card = Color.alphaBlend(cardPaint, scaffold);
  final cardOnWash = Color.alphaBlend(cardPaint, washed);
  final primary = data.colorScheme.primary;
  return {
    'scaffold': scaffold,
    'washed scaffold': washed,
    'card': card,
    'card on wash': cardOnWash,
    'selected row (8% primary)': Color.alphaBlend(
      primary.withValues(alpha: 0.08),
      cardOnWash,
    ),
    'soft well on card': Color.alphaBlend(aiUi.softBackgroundColor, card),
    'soft well on wash card': Color.alphaBlend(
      aiUi.softBackgroundColor,
      cardOnWash,
    ),
    'aiUi.cardColor': aiUi.cardColor,
    // 凹槽底（分段槽 / 首页节点胶囊）：浅色是不透明的 #E9EEF6，直接压在页底与
    // 晕染页底上；深色是 8% 白叠在页底上。
    'soft well on scaffold': Color.alphaBlend(
      aiUi.softBackgroundColor,
      scaffold,
    ),
    'soft well on wash': Color.alphaBlend(aiUi.softBackgroundColor, washed),
    'selected row on soft well': Color.alphaBlend(
      primary.withValues(alpha: 0.08),
      Color.alphaBlend(aiUi.softBackgroundColor, cardOnWash),
    ),
  };
}

void main() {
  group('延迟状态色对比度 ≥ 4.5:1（小字，WCAG AA）', () {
    for (final brightness in Brightness.values) {
      final surfaces = _surfaces(brightness);
      for (final band in LatencyBand.values) {
        test('${brightness.name} / ${band.name}', () {
          final color = StatusColors.latency(brightness, band);
          for (final entry in surfaces.entries) {
            expect(
              contrast(color, entry.value),
              greaterThanOrEqualTo(4.5),
              reason: '${band.name} 压在 ${entry.key} 上对比度不足',
            );
          }
        });
      }
    }
  });

  group('展示出来的每种延迟状态：按真实前景（含 alpha）先合成再算对比度 ≥ 4.5:1', () {
    // 从真实的 LatencyLabel 里读它实际渲染的颜色（不是基础常量），先把前景按它
    // 自己的 alpha 合成到各个真实底色上，再算 WCAG。以后谁给历史值 / 测量中旧值
    // 重新叠 alpha，这里会直接红。
    Widget host(LatencyDisplayState state, int? ms, Brightness b) =>
        ProviderScope(
          overrides: [
            translationsProvider.overrideWithValue(AppLocale.zhCn.buildSync()),
          ],
          child: MaterialApp(
            theme: b == Brightness.light
                ? AppTheme(AppThemeMode.light, 'Roboto').lightTheme()
                : AppTheme(AppThemeMode.dark, 'Roboto').darkTheme(),
            home: Scaffold(
              body: LatencyLabel(state: state, ms: ms),
            ),
          ),
        );

    final cases = <(LatencyDisplayState, int?)>[
      (LatencyDisplayState.untested, null),
      (LatencyDisplayState.timeout, null),
      (LatencyDisplayState.testing, null),
      for (final ms in [50, 299, 300, 799, 800, 5000]) ...[
        (LatencyDisplayState.success, ms),
        (LatencyDisplayState.stale, ms),
        (LatencyDisplayState.testing, ms),
      ],
    ];

    for (final brightness in Brightness.values) {
      testWidgets(brightness.name, (tester) async {
        final surfaces = _surfaces(brightness);
        for (final (state, ms) in cases) {
          await tester.pumpWidget(host(state, ms, brightness));
          final fg = tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(LatencyLabel),
                  matching: find.byType(Text),
                ),
              )
              .style!
              .color!;
          for (final entry in surfaces.entries) {
            final composited = Color.alphaBlend(fg, entry.value);
            expect(
              contrast(composited, entry.value),
              greaterThanOrEqualTo(4.5),
              reason: '$state ${ms ?? '-'}ms 压在 ${entry.key} 上对比度不足',
            );
          }
        }
      });
    }
  });

  test('超时色与最慢档同色，按明暗各自满足 4.5:1', () {
    for (final brightness in Brightness.values) {
      expect(
        StatusColors.latencyTimeout(brightness),
        StatusColors.latency(brightness, LatencyBand.slow),
      );
    }
  });

  test('分档边界：<300 快、300–799 中、≥800 慢', () {
    expect(latencyBandOf(0), LatencyBand.fast);
    expect(latencyBandOf(299), LatencyBand.fast);
    expect(latencyBandOf(300), LatencyBand.medium);
    expect(latencyBandOf(799), LatencyBand.medium);
    expect(latencyBandOf(800), LatencyBand.slow);
  });

  test('连接绿点（非文字标记）两套主题各自满足 ≥ 3:1', () {
    for (final brightness in Brightness.values) {
      final color = StatusColors.connected(brightness);
      for (final entry in _surfaces(brightness).entries) {
        expect(
          contrast(color, entry.value),
          greaterThanOrEqualTo(3.0),
          reason: '连接绿压在 ${entry.key} 上对比度不足（${brightness.name}）',
        );
      }
    }
  });

  group('ColorScheme 角色成对使用时对比度 ≥ 4.5:1', () {
    final theme = AppTheme(AppThemeMode.system, 'x');
    for (final entry in {
      Brightness.light: theme.lightTheme().colorScheme,
      Brightness.dark: theme.darkTheme().colorScheme,
    }.entries) {
      final scheme = entry.value;
      test('${entry.key.name}：primary/onPrimary', () {
        expect(
          contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
      });
      test('${entry.key.name}：primaryContainer/onPrimaryContainer', () {
        expect(
          contrast(scheme.primaryContainer, scheme.onPrimaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  test('品牌靛蓝原色压白只有 4.38:1（所以浅色 primary 用略深的 indigoOnLight）', () {
    expect(contrast(BrandColors.indigo, Colors.white), lessThan(4.5));
    expect(
      contrast(BrandColors.indigoOnLight, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
  });
}
