import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:clashmiao/shared/components/page_header.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(String title, TextDirection direction) => MaterialApp(
  theme: ThemeData.light().copyWith(
    extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
  ),
  builder: (context, child) =>
      Directionality(textDirection: direction, child: child!),
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: PageHeader(
        title: title,
        actions: [
          GlassIconButton(
            icon: FluentIcons.options_24_regular,
            tooltip: 'a',
            onTap: () {},
          ),
          GlassIconButton(
            icon: FluentIcons.add_24_regular,
            tooltip: 'b',
            filled: true,
            onTap: () {},
          ),
        ],
      ),
    ),
  ),
);

void main() {
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('PageHeader 320 dp / $scale× / ${direction.name}：长标题折行或省略，'
          '按钮不出屏、不重叠、与标题垂直居中，且标题带 header 语义', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final handle = tester.ensureSemantics();

        const title = 'ClashMiao Very Long Header Title';
        await tester.pumpWidget(_host(title, direction));

        expect(tester.takeException(), isNull);
        final headerRect = tester.getRect(find.byType(PageHeader));
        expect(headerRect.height, greaterThanOrEqualTo(48));
        final buttons = find.byType(GlassIconButton);
        final rects = [
          tester.getRect(buttons.at(0)),
          tester.getRect(buttons.at(1)),
        ];
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(320));
          expect(r.height, greaterThanOrEqualTo(48));
          expect(r.center.dy, closeTo(headerRect.center.dy, 0.5));
        }
        expect(rects[0].overlaps(rects[1]), isFalse);
        final titleRect = tester.getRect(find.text(title));
        expect(titleRect.overlaps(rects[0]), isFalse);
        expect(titleRect.overlaps(rects[1]), isFalse);
        expect(
          tester.getSemantics(find.text(title)),
          isSemantics(isHeader: true, label: title),
        );
        handle.dispose();
      });
    }
  }
}
