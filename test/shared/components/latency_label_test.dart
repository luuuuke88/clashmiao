import 'dart:math' as math;

import 'package:clashmiao/core/latency/latency_rules.dart';
import 'package:clashmiao/core/localization/translations.dart';
import 'package:clashmiao/core/theme/app_theme.dart';
import 'package:clashmiao/core/theme/app_theme_mode.dart';
import 'package:clashmiao/core/theme/brand_colors.dart';
import 'package:clashmiao/core/theme/status_colors.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/latency_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Widget _host(
  LatencyDisplayState state, {
  int? ms,
  Brightness brightness = Brightness.light,
}) {
  return ProviderScope(
    overrides: [translationsProvider.overrideWithValue(AppLocale.zhCn.build())],
    child: MaterialApp(
      theme: _appTheme(brightness),
      home: Scaffold(
        body: Center(
          child: LatencyLabel(state: state, ms: ms),
        ),
      ),
    ),
  );
}

/// App 实际使用的主题（不是测试里随手拼的 ThemeData），对比度要按它算。
ThemeData _appTheme(Brightness brightness) => brightness == Brightness.light
    ? AppTheme(AppThemeMode.light, 'Roboto').lightTheme()
    : AppTheme(AppThemeMode.dark, 'Roboto').darkTheme();

Text _text(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: find.byType(LatencyLabel), matching: find.byType(Text)),
);

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 把半透明前景压到不透明背景上。
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  group('五种延迟状态', () {
    testWidgets('未测：占位 —，不透明中性色', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.untested));
      final text = _text(tester);
      expect(text.data, '—');
      expect(
        text.style!.color,
        _appTheme(Brightness.light).colorScheme.onSurfaceVariant,
      );
      expect(text.style!.color!.a, 1.0);
    });

    testWidgets('测量中：有旧值保留旧值（中性色，不叠 alpha），无旧值是占位', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.testing, ms: 150));
      expect(_text(tester).data, '150ms');
      expect(
        _text(tester).style!.color,
        _appTheme(Brightness.light).colorScheme.onSurfaceVariant,
      );
      expect(_text(tester).style!.color!.a, 1.0);
      await tester.pumpWidget(_host(LatencyDisplayState.testing));
      expect(_text(tester).data, '—');
    });

    testWidgets('成功：数字 + 分档色（不叠 alpha）', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.success, ms: 120));
      var text = _text(tester);
      expect(text.data, '120ms');
      expect(
        text.style!.color,
        StatusColors.latency(Brightness.light, LatencyBand.fast),
      );
      expect(text.style!.color!.a, 1.0);

      await tester.pumpWidget(_host(LatencyDisplayState.success, ms: 500));
      expect(
        _text(tester).style!.color,
        StatusColors.latency(Brightness.light, LatencyBand.medium),
      );
      await tester.pumpWidget(_host(LatencyDisplayState.success, ms: 900));
      expect(
        _text(tester).style!.color,
        StatusColors.latency(Brightness.light, LatencyBand.slow),
      );
    });

    testWidgets('超时：显示「超时」', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.timeout));
      expect(_text(tester).data, '超时');
    });

    testWidgets('历史值：数字相同，用中性色弱化（与成功的分档色区分），不叠 alpha', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _host(LatencyDisplayState.stale, ms: 120, brightness: brightness),
        );
        await tester.pumpAndSettle(); // 等 MaterialApp 的主题切换动画走完
        final text = _text(tester);
        expect(text.data, '120ms');
        expect(
          text.style!.color,
          _appTheme(brightness).colorScheme.onSurfaceVariant,
        );
        expect(text.style!.color!.a, 1.0);
        expect(
          text.style!.color,
          isNot(StatusColors.latency(brightness, LatencyBand.fast)),
        );
      }
    });

    testWidgets('未测一律显示 —，即使传了数值（显示与语义一致）', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(LatencyDisplayState.untested, ms: 120));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('120ms'), findsNothing);
      expect(_text(tester).data, '—');
      expect(find.bySemanticsLabel('延迟: 未测试'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('120')), findsNothing);
      expect(
        LatencyLabel.displayText(
          AppLocale.zhCn.build(),
          LatencyDisplayState.untested,
          120,
        ),
        '—',
      );
      handle.dispose();
    });

    test('布局预算的数值取有效延迟上限，跟着 latency_rules 走', () {
      expect(LatencyLabel.budgetMs, kDelayTimeoutSentinelMs);
      expect(isMeasurableDelay(LatencyLabel.budgetMs), isTrue);
    });

    testWidgets('布局预算：不小于任一状态的实际宽度，并按样式 / 缩放 / 语言缓存', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.untested));
      final context = tester.element(find.byType(LatencyLabel));
      for (final locale in AppLocale.values) {
        final t = locale.build();
        final budget = LatencyLabel.budget(context, t);
        for (final text in [
          '—',
          '120ms',
          '9999ms',
          '10000ms',
          '${kDelayTimeoutSentinelMs}ms',
          t.proxies.delayTimeout,
        ]) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(
                context,
              ).style.merge(LatencyLabel.baseStyle(13)),
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          expect(
            budget.width,
            greaterThanOrEqualTo(painter.width - 0.01),
            reason: '${locale.name} 「$text」超出了预算',
          );
          painter.dispose();
        }
        // 同一组参数第二次取：直接命中缓存（同一个对象），不再重新测量。
        expect(identical(LatencyLabel.budget(context, t), budget), isTrue);
      }
    });

    testWidgets('等宽数字，且不会换行', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.success, ms: 88));
      final text = _text(tester);
      expect(
        text.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(text.maxLines, 1);
    });

    testWidgets('语义标签随状态变化', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(LatencyDisplayState.success, ms: 120));
      expect(find.bySemanticsLabel('延迟: 120ms'), findsOneWidget);
      await tester.pumpWidget(_host(LatencyDisplayState.timeout));
      expect(find.bySemanticsLabel('延迟测试超时'), findsOneWidget);
      await tester.pumpWidget(_host(LatencyDisplayState.testing));
      expect(find.bySemanticsLabel('正在测试延迟'), findsOneWidget);
      await tester.pumpWidget(_host(LatencyDisplayState.untested));
      expect(find.bySemanticsLabel('延迟: 未测试'), findsOneWidget);
      await tester.pumpWidget(_host(LatencyDisplayState.stale, ms: 90));
      expect(find.bySemanticsLabel('延迟: 90ms（历史值）'), findsOneWidget);
      handle.dispose();
    });
  });

  group('延迟分档', () {
    test('<300 / 300–799 / ≥800 ms 三档', () {
      expect(latencyBandOf(1), LatencyBand.fast);
      expect(latencyBandOf(299), LatencyBand.fast);
      expect(latencyBandOf(300), LatencyBand.medium);
      expect(latencyBandOf(799), LatencyBand.medium);
      expect(latencyBandOf(800), LatencyBand.slow);
      expect(latencyBandOf(5000), LatencyBand.slow);
    });
  });

  group('小字对比度 ≥ 4.5:1（WCAG，按实际合成底色）', () {
    // 每种状态、每个数值档位，取标签实际渲染出来的颜色（从组件里读，而不是
    // 在测试里另算一份），压到它真实所在的底色上：
    //   页面底 = scaffold 色 + BrandBackdrop 的品牌晕染（靛蓝、金色两团径向
    //            渐变，按峰值透明度计；两团叠在一起是保守上界）；
    //   代理页普通行 = 页面底 + GlassCard 的半透明卡片色；
    //   代理页选中行 = 普通行 + 8% 品牌色 Ink；
    //   首页节点胶囊 = 页面底 + softBackgroundColor。
    Map<String, Color> surfaces(ThemeData theme) {
      final light = theme.brightness == Brightness.light;
      final ai = theme.extension<AiUiTheme>()!;
      final base = theme.scaffoldBackgroundColor;
      final indigo = BrandColors.indigo.withValues(alpha: light ? 0.16 : 0.22);
      final gold = BrandColors.gold.withValues(alpha: light ? 0.14 : 0.07);
      final pages = <String, Color>{
        '无晕染': base,
        '靛蓝晕染': _over(indigo, base),
        '金色晕染': _over(gold, base),
        '靛蓝+金色': _over(gold, _over(indigo, base)),
        '金色+靛蓝': _over(indigo, _over(gold, base)),
      };
      final card = light
          ? Colors.white.withValues(alpha: 0.72)
          : const Color(0xFF1C1C22).withValues(alpha: 0.62);
      final selectedTint = theme.colorScheme.primary.withValues(alpha: 0.08);
      return {
        for (final page in pages.entries) ...{
          '普通行/${page.key}': _over(card, page.value),
          '选中行/${page.key}': _over(selectedTint, _over(card, page.value)),
          '首页胶囊/${page.key}': _over(ai.softBackgroundColor, page.value),
        },
      };
    }

    final cases = <(LatencyDisplayState, int?)>[
      (LatencyDisplayState.untested, null),
      (LatencyDisplayState.timeout, null),
      (LatencyDisplayState.testing, null),
      for (final ms in [120, 500, 900]) ...[
        (LatencyDisplayState.success, ms),
        (LatencyDisplayState.stale, ms),
        (LatencyDisplayState.testing, ms),
      ],
    ];

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}：五种状态（含历史值、测量中旧值）在所有底色上都 ≥ 4.5', (
        tester,
      ) async {
        final bgs = surfaces(_appTheme(brightness));
        final report = <String>[];
        for (final (state, ms) in cases) {
          await tester.pumpWidget(_host(state, ms: ms, brightness: brightness));
          final fg = _text(tester).style!.color!;
          var worst = double.infinity;
          var worstOn = '';
          for (final bg in bgs.entries) {
            final ratio = _contrast(_over(fg, bg.value), bg.value);
            if (ratio < worst) {
              worst = ratio;
              worstOn = bg.key;
            }
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$state ${ms ?? '-'}ms on ${bg.key}: $ratio',
            );
          }
          report.add(
            '$state ${ms ?? '-'}: ${worst.toStringAsFixed(2)} ($worstOn)',
          );
        }
        // 方便在报告里引用最差值。
        debugPrint('[contrast ${brightness.name}] ${report.join(' | ')}');
      });
    }

    test('所有状态都不叠 alpha（弱化靠中性色，不靠透明度）', () {
      for (final brightness in Brightness.values) {
        final theme = _appTheme(brightness);
        expect(latencyNeutralColor(theme).a, 1.0);
        for (final band in LatencyBand.values) {
          expect(StatusColors.latency(brightness, band).a, 1.0);
        }
      }
    });
  });
}
