import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/glass_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {required Brightness brightness}) {
  return tester.pumpWidget(
    MaterialApp(
      theme:
          (brightness == Brightness.light
                  ? ThemeData.light()
                  : ThemeData.dark())
              .copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  brightness == Brightness.light
                      ? AiUiTheme.light
                      : AiUiTheme.dark,
                ],
              ),
      home: const Scaffold(
        body: Center(child: GlassCard(child: Text('内容'))),
      ),
    ),
  );
}

void main() {
  testWidgets('卡片不用 BackdropFilter——一屏五六张的话动画会被拖垮', (tester) async {
    await _pump(tester, brightness: Brightness.light);
    expect(
      find.descendant(
        of: find.byType(GlassCard),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('卡片底色留着透明度，底下的品牌晕染要透得上来', (tester) async {
    await _pump(tester, brightness: Brightness.light);

    final fill = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassCard),
        matching: find.byType(Container),
      ),
    );
    final decoration = fill.decoration! as BoxDecoration;
    expect(
      decoration.color!.a,
      lessThan(1.0),
      reason: '实色底就不是玻璃了——底下的品牌晕染要透得上来',
    );
    expect(decoration.color!.a, greaterThan(0.5), reason: '太透的话卡片里的文字会被背景吃掉');
  });

  testWidgets('深色主题下用深色玻璃，不是浅色玻璃', (tester) async {
    await _pump(tester, brightness: Brightness.dark);

    final fill = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassCard),
        matching: find.byType(Container),
      ),
    );
    final color = (fill.decoration! as BoxDecoration).color!;
    expect(color.r, lessThan(0.3));
    expect(color.g, lessThan(0.3));
    expect(color.b, lessThan(0.3));
  });

  group('描边颜色', () {
    Future<void> pumpWith(
      WidgetTester tester, {
      required Color? borderColor,
      bool disableAnimations = false,
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.dark],
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: GlassCard(
                borderColor: borderColor,
                borderWidth: borderColor == null ? 1 : 1.5,
                child: const Text('内容'),
              ),
            ),
          ),
        ),
      );
    }

    Border border(WidgetTester tester) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(GlassCard),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration! as BoxDecoration).border! as Border;
    }

    testWidgets('选中时描边颜色渐变到品牌色，中途是两端之间的颜色', (tester) async {
      await pumpWith(tester, borderColor: null);
      final from = border(tester).top.color;

      await pumpWith(tester, borderColor: Colors.red);
      await tester.pump(const Duration(milliseconds: 60));
      final mid = border(tester).top.color;
      expect(mid, isNot(from));
      expect(mid, isNot(Colors.red));

      await tester.pump(const Duration(milliseconds: 300));
      expect(border(tester).top.color, Colors.red);
      // 宽度不渐变：由调用方同步调整内边距来抵消，渐变会让卡片忽大忽小。
      expect(border(tester).top.width, 1.5);
    });

    testWidgets('减少动画：描边颜色立刻到位', (tester) async {
      await pumpWith(tester, borderColor: null, disableAnimations: true);
      await pumpWith(tester, borderColor: Colors.red, disableAnimations: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(border(tester).top.color, Colors.red);
    });
  });
}
