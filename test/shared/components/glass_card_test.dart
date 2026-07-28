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
}
