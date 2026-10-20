import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/page_header.dart';
import 'package:clashmiao/shared/components/sub_page_scaffold.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  List<Widget> actions = const [],
  VoidCallback? onClose,
  Widget? titleWidget,
  String? title = '标题',
}) => MaterialApp(
  theme: ThemeData.light().copyWith(
    extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SubPageScaffold(
                title: title,
                titleWidget: titleWidget,
                actions: actions,
                closeLabel: '关闭',
                onClose: onClose,
                body: ListView(
                  children: [
                    for (var i = 0; i < 60; i++)
                      SizedBox(height: 56, child: Text('row $i')),
                  ],
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('页头就是项目的 PageHeader：24 sp 粗体标题、header 语义、无 AppBar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await _open(tester);

    expect(find.byType(PageHeader), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    final style = tester.widget<Text>(find.text('标题')).style!;
    expect(style.fontSize, 24);
    expect(style.fontWeight, FontWeight.w800);
    expect(
      tester.getSemantics(find.text('标题')),
      isSemantics(label: '标题', isHeader: true),
    );
    // 24 dp 页头边距，与配置页一致。
    expect(tester.getTopLeft(find.text('标题')).dx, 24);
    handle.dispose();
  });

  testWidgets('页头固定：内容滚动时页头不动', (tester) async {
    await tester.pumpWidget(_app());
    await _open(tester);
    final before = tester.getTopLeft(find.text('标题'));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('标题')), before);
  });

  testWidgets('关闭格永远在胶囊最后；点它等同返回', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        actions: [
          HeaderPillButton(
            icon: FluentIcons.search_24_regular,
            label: '搜索',
            onTap: () => taps++,
          ),
        ],
      ),
    );
    await _open(tester);
    final search = tester.getCenter(find.byIcon(FluentIcons.search_24_regular));
    final close = tester.getCenter(find.byIcon(FluentIcons.dismiss_24_regular));
    expect(search.dx, lessThan(close.dx));

    await tester.tap(find.byIcon(FluentIcons.search_24_regular));
    expect(taps, 1);

    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    await tester.pumpAndSettle();
    expect(find.byType(SubPageScaffold), findsNothing);
  });

  testWidgets('onClose 可接管（搜索态先收起再返回）', (tester) async {
    var closes = 0;
    await tester.pumpWidget(_app(onClose: () => closes++));
    await _open(tester);
    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(find.byType(SubPageScaffold), findsOneWidget, reason: '没有被默认返回');
  });

  testWidgets('胶囊按钮可聚焦、键盘 Enter 触发，并带按钮语义与标签', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await _open(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('关闭')),
      isSemantics(label: '关闭', isButton: true, hasEnabledState: true),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SubPageScaffold), findsNothing);
    handle.dispose();
  });

  testWidgets('titleWidget 与文字标题占同一个位置（搜索输入框）', (tester) async {
    await tester.pumpWidget(
      _app(title: null, titleWidget: const TextField(key: ValueKey('q'))),
    );
    await _open(tester);
    expect(find.byKey(const ValueKey('q')), findsOneWidget);
    expect(find.byType(PageHeader), findsOneWidget);
  });
}
