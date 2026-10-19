import 'dart:math' as math;

import 'package:clashmiao/core/localization/translations.dart';
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
      theme: ThemeData(
        brightness: brightness,
        extensions: <ThemeExtension<dynamic>>[
          brightness == Brightness.light ? AiUiTheme.light : AiUiTheme.dark,
        ],
      ),
      home: Scaffold(
        body: Center(
          child: LatencyLabel(state: state, ms: ms),
        ),
      ),
    ),
  );
}

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
    testWidgets('未测：占位 —，次要文字色', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.untested));
      final text = _text(tester);
      expect(text.data, '—');
      expect(text.style!.color, AiUiTheme.light.secondaryTextColor);
    });

    testWidgets('测量中：有旧值保留旧值，无旧值是占位', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.testing, ms: 150));
      expect(_text(tester).data, '150ms');
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

    testWidgets('历史值：数字相同，但不透明度低于成功状态', (tester) async {
      await tester.pumpWidget(_host(LatencyDisplayState.stale, ms: 120));
      final text = _text(tester);
      expect(text.data, '120ms');
      expect(text.style!.color!.a, lessThan(1.0));
      expect(text.style!.color!.a, kStaleLatencyOpacity);
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

  group('小字对比度 ≥ 4.5:1（WCAG）', () {
    // 浅色：纯白、页面底色、带 12% 品牌色晕染的页面底、选中行 8% 品牌底。
    const primary = Color(0xFF6A64F8);
    final lightSurfaces = <String, Color>{
      '白卡片': Colors.white,
      '页面底': const Color(0xFFF8FAFC),
      '带晕染的页面底': _over(
        primary.withValues(alpha: 0.12),
        const Color(0xFFF8FAFC),
      ),
      '选中行（白底）': _over(primary.withValues(alpha: 0.08), Colors.white),
      '选中行（晕染底）': _over(
        primary.withValues(alpha: 0.08),
        _over(primary.withValues(alpha: 0.12), const Color(0xFFF8FAFC)),
      ),
    };
    final darkSurfaces = <String, Color>{
      '纯黑页底': Colors.black,
      '卡片': const Color(0xFF1C1C22),
      '选中行': _over(
        const Color(0xFF8E8AFF).withValues(alpha: 0.08),
        const Color(0xFF1C1C22),
      ),
    };

    test('浅色主题：三档色与超时色在各种卡片底上都 ≥ 4.5', () {
      for (final band in LatencyBand.values) {
        final color = StatusColors.latency(Brightness.light, band);
        for (final entry in lightSurfaces.entries) {
          expect(
            _contrast(color, entry.value),
            greaterThanOrEqualTo(4.5),
            reason: '$band on ${entry.key}',
          );
        }
      }
    });

    test('深色主题：三档色在卡片底上都 ≥ 4.5', () {
      for (final band in LatencyBand.values) {
        final color = StatusColors.latency(Brightness.dark, band);
        for (final entry in darkSurfaces.entries) {
          expect(
            _contrast(color, entry.value),
            greaterThanOrEqualTo(4.5),
            reason: '$band on ${entry.key}',
          );
        }
      }
    });

    test('未测占位（次要文字色）在两套主题的卡片上也 ≥ 4.5', () {
      final lightText = AiUiTheme.light.secondaryTextColor;
      for (final bg in lightSurfaces.values) {
        expect(_contrast(_over(lightText, bg), bg), greaterThanOrEqualTo(4.5));
      }
      final darkText = AiUiTheme.dark.secondaryTextColor;
      for (final bg in darkSurfaces.values) {
        expect(_contrast(_over(darkText, bg), bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('历史值（压低不透明度）仍 ≥ 3:1，保证看得清', () {
      for (final band in LatencyBand.values) {
        final color = StatusColors.latency(
          Brightness.light,
          band,
        ).withValues(alpha: kStaleLatencyOpacity);
        expect(
          _contrast(_over(color, Colors.white), Colors.white),
          greaterThanOrEqualTo(3.0),
          reason: '$band',
        );
      }
    });
  });
}
