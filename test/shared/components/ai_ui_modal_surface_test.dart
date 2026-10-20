import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('毛玻璃弹层的底色足够实，盖得住后面的页面（$brightness）', (tester) async {
      final base = brightness == Brightness.light
          ? ThemeData.light()
          : ThemeData.dark();
      final theme = base.copyWith(
        extensions: <ThemeExtension<dynamic>>[
          brightness == Brightness.light ? AiUiTheme.light : AiUiTheme.dark,
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: AiUiModalWrapper(child: Text('内容')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fills = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AiUiModalWrapper),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>();
      expect(
        fills.any((c) => c.a >= kModalSurfaceAlpha - 0.001),
        isTrue,
        reason: '底色太透明时，页面上的开关与卡片会模糊成色块叠在选项文字后面',
      );
      expect(fills, contains(modalSurfaceColor(theme)));
    });
  }
}
