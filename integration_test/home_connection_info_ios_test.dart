import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/model/box_status.dart';
import 'package:clashmiao/core/model/outbound.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/home/widget/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'mobile home connected info matches one-line layout',
    (tester) async {
      if (!Platform.isAndroid && !Platform.isIOS) {
        markTestSkipped('mobile-only UI screenshot helper');
        return;
      }

      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          outboundGroupsProvider.overrideWith(
            (_) => Stream<List<OutboundGroup>>.value(const [
              OutboundGroup(
                tag: 'proxy',
                type: 'selector',
                selected: '香港 01 | SS',
                items: [
                  OutboundProxy(
                    tag: '香港 01 | SS',
                    type: 'shadowsocks',
                    delay: 128,
                  ),
                ],
              ),
            ]),
          ),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: const Scaffold(
              body: Center(child: ConnectionInfoForTest(status: BoxStarted())),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('香港 01 | SS'), findsOneWidget);
      expect(find.text('128ms'), findsOneWidget);
      expect(find.textContaining('已连接 '), findsNothing);

      if (const bool.fromEnvironment('CLASHMIAO_EMIT_HOME_INFO_SCREENSHOT')) {
        if (Platform.isAndroid) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
        }
        final screenshot = await binding.takeScreenshot(
          'clashmiao-home-connected-info',
        );
        // ignore: avoid_print
        print('[home-info-ios-base64-begin]');
        // ignore: avoid_print
        print(base64Encode(screenshot));
        // ignore: avoid_print
        print('[home-info-ios-base64-end]');
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
