import 'dart:io';

import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/ai_ui_modal_wrapper.dart';
import 'package:clashmiao/shared/components/modal_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(Brightness b) => ModalTokens.apply(
  (b == Brightness.light ? ThemeData.light() : ThemeData.dark()).copyWith(
    extensions: <ThemeExtension<dynamic>>[
      b == Brightness.light ? AiUiTheme.light : AiUiTheme.dark,
    ],
  ),
);

Widget _host(Brightness b, void Function(BuildContext) open) => MaterialApp(
  theme: _theme(b),
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(onPressed: () => open(context), child: const Text('go')),
    ),
  ),
);

Color? _scrimColor(WidgetTester tester) =>
    tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color;

void main() {
  for (final b in Brightness.values) {
    group('主题 token（${b.name}）', () {
      test('apply 写入遮罩与圆角', () {
        final t = _theme(b);
        expect(t.bottomSheetTheme.modalBarrierColor, ModalTokens.scrim);
        expect(
          (t.bottomSheetTheme.shape! as RoundedRectangleBorder).borderRadius,
          ModalTokens.topRadius,
        );
        expect(t.dialogTheme.barrierColor, ModalTokens.scrim);
        expect(
          (t.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          ModalTokens.dialogRadius,
        );
      });

      testWidgets('裸 showModalBottomSheet 取到统一遮罩', (tester) async {
        await tester.pumpWidget(
          _host(
            b,
            (c) => showModalBottomSheet<void>(
              context: c,
              builder: (_) => const SizedBox(height: 100),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(_scrimColor(tester), ModalTokens.scrim);
      });

      testWidgets('showAiUiModal：同一遮罩，表面圆角是 token', (tester) async {
        await tester.pumpWidget(
          _host(
            b,
            (c) => showAiUiModal<void>(
              context: c,
              builder: (_) => const AiUiModalWrapper(child: Text('内容')),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(_scrimColor(tester), ModalTokens.scrim);
        final radii = tester
            .widgetList<ClipRRect>(
              find.descendant(
                of: find.byType(AiUiModalWrapper),
                matching: find.byType(ClipRRect),
              ),
            )
            .map((w) => w.borderRadius);
        expect(radii, contains(ModalTokens.topRadius));
      });

      testWidgets('showDialog：同一遮罩，AlertDialog 圆角是 token', (tester) async {
        await tester.pumpWidget(
          _host(
            b,
            (c) => showDialog<void>(
              context: c,
              builder: (_) => const AlertDialog(title: Text('标题')),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pumpAndSettle();
        expect(_scrimColor(tester), ModalTokens.scrim);
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        final shape =
            (dialog.shape ??
                    Theme.of(tester.element(find.byType(Dialog)))
                        .dialogTheme
                        .shape)
                as RoundedRectangleBorder;
        expect(shape.borderRadius, ModalTokens.dialogRadius);
      });
    });
  }

  test('应用主题（app.dart）两套都套了弹层 token', () {
    final src = File('lib/app/app.dart').readAsStringSync();
    expect(src, contains('theme: ModalTokens.apply(theme.lightTheme())'));
    expect(src, contains('darkTheme: ModalTokens.apply(theme.darkTheme())'));
  });

  test('调用点不写遮罩色与弹层圆角字面量，一律走 token', () {
    final offenders = <String>[];
    for (final root in ['lib/features', 'lib/shared', 'lib/app']) {
      for (final e in Directory(root).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final path = e.path.replaceAll('\\', '/');
        if (path == 'lib/shared/components/modal_tokens.dart') continue;
        final lines = e.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('barrierColor:')) offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '遮罩色统一取主题里的 ModalTokens.scrim');

    final wrapper = File('lib/shared/components/ai_ui_modal_wrapper.dart')
        .readAsStringSync();
    expect(wrapper.contains('Radius.circular(32)'), isFalse);
    final quick = File(
      'lib/features/home/presentation/quick_settings_modal.dart',
    ).readAsStringSync();
    expect(quick.contains('Radius.circular(24)'), isFalse);
  });
}
