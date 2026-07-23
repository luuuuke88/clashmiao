import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/analytics_toggle_tile.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AnalyticsToggleTile] 共享组件的测试。
///
/// 统一视觉标准选的是项目里对"设置项 + 开关"占主导地位的单行样式——
/// `settings_page.dart` 的 `_SwitchSettingsTile`/`_SettingsTile`、
/// `config_options_page.dart` 的 `_ConfigGroup` 内部条目、
/// `profile_details_page.dart` 的 `_GlassContainer` 内部条目都是这个样式
/// （共享卡片容器 + 分隔线分隔的单行）。之前 `onboarding_page.dart` 私有的
/// `_IntroSwitchTile` 是另一套"每项独立卡片"的样式，跟 `settings_page.dart`
/// 私有的 `_BoolPreferenceTile` 视觉不一致，两者控制的却是同一个持久化偏好
/// （`clashmiao_analytics_enabled`）。这里把两处收敛成本组件。
void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    String label = '启用分析',
    String? subtitle,
    bool value = false,
    ValueChanged<bool>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: Scaffold(
          body: AnalyticsToggleTile(
            label: label,
            subtitle: subtitle,
            value: value,
            onChanged: onChanged ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('渲染图标和文案', (tester) async {
    await pumpTile(tester, label: '启用分析');

    expect(find.text('启用分析'), findsOneWidget);
    expect(find.byIcon(FluentIcons.bug_24_regular), findsOneWidget);
  });

  testWidgets('value=false 时开关处于关闭状态', (tester) async {
    await pumpTile(tester, value: false);

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isFalse);
  });

  testWidgets('value=true 时开关处于打开状态', (tester) async {
    await pumpTile(tester, value: true);

    final switchWidget = tester.widget<Switch>(find.byType(Switch));
    expect(switchWidget.value, isTrue);
  });

  testWidgets('传入 subtitle 时展示副标题文案', (tester) async {
    await pumpTile(tester, subtitle: '用于改进应用的说明文案');

    expect(find.text('用于改进应用的说明文案'), findsOneWidget);
  });

  testWidgets('不传 subtitle 时不渲染副标题、整行固定高度 56', (tester) async {
    await pumpTile(tester);

    final size = tester.getSize(find.byType(AnalyticsToggleTile));
    expect(size.height, 56);
  });

  testWidgets('点击整行会以取反后的值调用 onChanged', (tester) async {
    bool? received;
    await pumpTile(tester, value: false, onChanged: (v) => received = v);

    await tester.tap(find.byType(AnalyticsToggleTile));
    await tester.pump();

    expect(received, isTrue);
  });

  testWidgets('点击开关本身也会以取反后的值调用 onChanged', (tester) async {
    bool? received;
    await pumpTile(tester, value: true, onChanged: (v) => received = v);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(received, isFalse);
  });
}
