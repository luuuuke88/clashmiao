import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/glass_icon_button.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback? onTap,
  String? tooltip,
  bool filled = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Scaffold(
        body: Center(
          child: GlassIconButton(
            icon: FluentIcons.add_24_regular,
            onTap: onTap,
            tooltip: tooltip,
            filled: filled,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('交互区至少 48x48，视觉圆仍是 40', (tester) async {
    await _pump(tester, onTap: () {});

    final hit = tester.getSize(
      find.descendant(
        of: find.byType(GlassIconButton),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(hit.width, greaterThanOrEqualTo(48));
    expect(hit.height, greaterThanOrEqualTo(48));

    // 圆本体（带 BoxDecoration 的 Container）没有变大。
    final circle = tester.getSize(
      find.descendant(
        of: find.byType(GlassIconButton),
        matching: find.byType(ClipOval),
      ),
    );
    expect(circle, const Size(40, 40));
  });

  testWidgets('点圆外 4 dp 的留白也算点中（实心款同理）', (tester) async {
    for (final filled in [false, true]) {
      var taps = 0;
      await _pump(tester, onTap: () => taps++, filled: filled);

      final center = tester.getCenter(find.byType(GlassIconButton));
      // 圆半径 20，热区半宽 24：偏移 22 落在圆外、热区内。
      await tester.tapAt(center + const Offset(22, 0));
      await tester.pump();
      expect(taps, 1, reason: 'filled=$filled');

      await tester.tapAt(center + const Offset(30, 0));
      await tester.pump();
      expect(taps, 1, reason: '热区之外不该触发');
    }
  });

  testWidgets('传入 tooltip 时真正构建 Tooltip，并作为无障碍标签', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, onTap: () {}, tooltip: '添加订阅');

    final tip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, '添加订阅');
    expect(find.bySemanticsLabel('添加订阅'), findsOneWidget);

    // 长按出可见提示。
    await tester.longPress(find.byType(GlassIconButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('添加订阅'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    handle.dispose();
  });

  testWidgets('没有 tooltip 时不构建 Tooltip', (tester) async {
    await _pump(tester, onTap: () {});
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('通过 Android 点按目标无障碍规范', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, onTap: () {}, tooltip: '添加订阅');
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
