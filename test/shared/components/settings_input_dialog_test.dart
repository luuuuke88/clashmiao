import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/settings_input_dialog.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    child: MaterialApp(
      theme: ThemeData.light().copyWith(
        extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
      ),
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  SettingsInputDialog<int>(
                    title: '自动更新间隔（小时）',
                    initialValue: 6,
                    icon: FluentIcons.arrow_sync_24_regular,
                    digitsOnly: true,
                    optionalAction: ('禁用', () {}),
                    validator: (value) => int.tryParse(value) != null,
                    mapTo: int.tryParse,
                  ).show(context);
                },
                child: const Text('open-input'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('SettingsInputDialog keeps modal controls', (
    tester,
  ) async {
    await tester.pumpWidget(await _host());
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('open-input'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('自动更新间隔（小时）'), findsWidgets);
    expect(find.byIcon(FluentIcons.arrow_sync_24_regular), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('禁用'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding ==
                const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
  });
}
