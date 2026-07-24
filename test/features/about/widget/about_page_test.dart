import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/build_config.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/about/widget/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
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
        home: const AboutPage(),
      ),
    ),
  );
}

void main() {
  testWidgets('AboutPage renders app overview', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    expect(find.text('About ClashMiao'), findsOneWidget);
    expect(find.text('ClashMiao'), findsOneWidget);
    expect(find.text('VERSION 1.2.3 (BUILD 45)'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    // 源代码有兜底默认 URL（见 build_config.dart 的 githubRepoUrl），永远可用
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('MADE WITH LOVE FOR CATS'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding == const EdgeInsets.only(top: 48),
      ),
      findsOneWidget,
    );
    expect(
      find.text('© 2024 ClashMiao Studio. All Rights Reserved.'),
      findsOneWidget,
    );
    expect(find.byType(SliverFillRemaining), findsOneWidget);
  });

  // 这些外链靠编译期 --dart-define 注入。以前没配置时行为是"入口还在、点了
  // 什么都不发生"——用户会认为这个 App 有坏按钮，而不是"这个功能没提供"。
  // 现在改成没配置就不显示入口。测试环境里这些 dart-define 天然是空的，
  // 正好覆盖"未配置"这条分支。
  testWidgets('未配置外链时不显示对应入口（不给死链）', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    expect(
      hasTelegramChannel || hasPrivacyPolicy,
      isFalse,
      reason: '前置条件：测试环境不该注入这些 dart-define，否则下面的断言没有意义',
    );

    await tester.pumpWidget(await _host());
    await tester.pumpAndSettle();

    expect(find.text('Telegram 频道'), findsNothing);
    expect(find.text('隐私政策'), findsNothing);
  });
}
