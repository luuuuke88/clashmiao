import 'dart:io';
import 'dart:convert';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/home/widget/quick_settings_modal.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'iOS quick settings modal screenshot hold',
    (tester) async {
      if (!Platform.isIOS) {
        markTestSkipped('ios-only UI screenshot helper');
        return;
      }

      final container = ProviderContainer(
        overrides: [boxServiceProvider.overrideWithValue(StubBoxService())],
      );
      await container.read(sharedPreferencesProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ClashMiaoApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      final quickSettingsButton = find.byIcon(FluentIcons.options_24_regular);
      expect(quickSettingsButton, findsOneWidget);

      await tester.tap(quickSettingsButton);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(QuickSettingsModal), findsOneWidget);
      if (const bool.fromEnvironment(
        'CLASHMIAO_EMIT_QUICK_SETTINGS_SCREENSHOT',
      )) {
        final screenshot = await binding.takeScreenshot(
          'clashmiao-quick-settings',
        );
        // Printed to a redirected host log and decoded after the test run.
        // ignore: avoid_print
        print('[quick-settings-ios-base64-begin]');
        // ignore: avoid_print
        print(base64Encode(screenshot));
        // ignore: avoid_print
        print('[quick-settings-ios-base64-end]');
      }
      // Keep the app in this state long enough for an external simctl screenshot.
      await tester.pump(const Duration(seconds: 20));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
