import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/confirmation_dialogs.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Confirmation dialog keeps modal layout and returns result',
    (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showConfirmationDialog(
                        context,
                        title: '删除',
                        message: '要永久删除配置文件吗？',
                        icon: FluentIcons.delete_24_regular,
                      );
                    },
                    child: const Text('open-confirm'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-confirm'));
      await tester.pumpAndSettle();

      expect(find.text('删除'), findsOneWidget);
      expect(find.text('要永久删除配置文件吗？'), findsOneWidget);
      expect(find.byIcon(FluentIcons.delete_24_regular), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    },
  );
}
