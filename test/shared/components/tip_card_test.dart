import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/tip_card.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TipCard] 共享组件的测试。
///
/// 统一视觉标准选的是项目里占主导地位的"玻璃拟态"（aiUi token 驱动）风格
/// ——之前 `config_options_page.dart` 里的私有 `_TipCard` 已经是这个风格,
/// `assets_page.dart` 里的另一份私有 `_TipCard` 则是朴素 `Card` 样式,
/// 两者互不一致。这里把 config_options_page 的版本收敛成共享组件。
void main() {
  Future<void> pumpTipCard(
    WidgetTester tester, {
    String message = '有部分文件缺失，建议下载。',
    IconData? icon,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
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
        home: Scaffold(
          body: icon == null
              ? TipCard(message: message)
              : TipCard(message: message, icon: icon),
        ),
      ),
    );
  }

  testWidgets('渲染提示文案和默认的灯泡图标', (tester) async {
    await pumpTipCard(tester, message: '有部分文件缺失，建议下载。');

    expect(find.text('有部分文件缺失，建议下载。'), findsOneWidget);
    expect(find.byIcon(FluentIcons.lightbulb_24_regular), findsOneWidget);
  });

  testWidgets('可以自定义图标', (tester) async {
    await pumpTipCard(tester, icon: FluentIcons.warning_24_regular);

    expect(find.byIcon(FluentIcons.warning_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.lightbulb_24_regular), findsNothing);
  });

  testWidgets('视觉参数：玻璃拟态背景色来自 aiUi.glassColor、圆角16、外边距 h12/v4', (
    tester,
  ) async {
    await pumpTipCard(tester);

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(TipCard),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(container.margin, const EdgeInsets.symmetric(horizontal: 12, vertical: 4));
    expect(decoration.borderRadius, BorderRadius.circular(16));
    expect(decoration.color, AiUiTheme.light.glassColor);
    expect(
      decoration.border,
      Border.all(color: AiUiTheme.light.borderColor.withValues(alpha: 0.08)),
    );
  });

  testWidgets('深色主题下取 dark token 的 glassColor', (tester) async {
    await pumpTipCard(tester, brightness: Brightness.dark);

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(TipCard),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, AiUiTheme.dark.glassColor);
  });
}
