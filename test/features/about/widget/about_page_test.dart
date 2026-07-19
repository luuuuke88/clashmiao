import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
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
      boxServiceProvider.overrideWithValue(StubBoxService()),
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
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('Telegram 频道'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
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
}
