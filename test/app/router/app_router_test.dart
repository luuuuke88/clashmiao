import 'package:clashmiao/app/router/app_router.dart';
import 'package:clashmiao/app/shell_page.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/model/box_stats.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  testWidgets('空偏好冷启动直接进入主页面', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
        profileListProvider.overrideWith((_) => Future.value(const [])),
        activeProfileProvider.overrideWith((_) => Future.value(null)),
        offlineProxyGroupsProvider.overrideWith((_) => Future.value(const [])),
        outboundGroupsProvider.overrideWith(
          (_) => Stream<List<OutboundGroup>>.value(const []),
        ),
        boxStatsProvider.overrideWith((_) => Stream.value(BoxStats.empty)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp.router(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            routerConfig: appRouter,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShellPage), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom_nav_0')), findsOneWidget);
    expect(prefs.containsKey('onboarding_done'), isFalse);
  });
}
