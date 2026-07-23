import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/assets/widget/assets_page.dart';
import 'package:clashmiao/shared/components/tip_card.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: ToastificationWrapper(
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: const AssetsPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('AssetsPage renders geo asset overview', (tester) async {
    await tester.pumpWidget(await _host());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('路由资源文件'), findsOneWidget);
    expect(find.text('GeoIP ›'), findsOneWidget);
    expect(find.text('Geosite ›'), findsOneWidget);
    expect(find.text('geoip-cn.srs'), findsOneWidget);
    expect(find.text('geosite-cn.srs'), findsOneWidget);
    expect(find.text('文件丢失'), findsNWidgets(2));

    // 两个资源都缺失时应该显示共享的提示卡片（跟 config_options_page 用
    // 的是同一个 TipCard 组件，风格统一——见 tip_card_test.dart）。
    expect(find.byType(TipCard), findsOneWidget);
  });

  testWidgets('AssetsPage add recommended menu is enabled', (tester) async {
    await tester.pumpWidget(await _host());
    await tester.pump(const Duration(milliseconds: 200));

    // flutter test 默认把 defaultTargetPlatform 判定为 android（见
    // adaptive_icon_test.dart 的说明），所以"更多"菜单图标渲染的是纵向
    // 三点（more_vertical），而不是之前硬编码的横向三点。
    await tester.tap(find.byIcon(FluentIcons.more_vertical_24_regular).first);
    await tester.pumpAndSettle();

    final menuItem = find.text('添加建议的资源文件');
    expect(menuItem, findsOneWidget);

    await tester.tap(menuItem);
    await tester.pumpAndSettle();

    expect(menuItem, findsNothing);
    expect(find.text('geoip-cn.srs'), findsOneWidget);
    expect(find.text('geosite-cn.srs'), findsOneWidget);
  });
}
