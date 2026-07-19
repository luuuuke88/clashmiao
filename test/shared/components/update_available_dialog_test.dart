import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/shared/components/update_available_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _host({
  required Future<void> Function(String url)? openUrl,
  String updateUrl = 'https://example.com/download',
}) async {
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
                  showUpdateAvailableDialog(
                    context,
                    currentVersion: '1.0.0',
                    latestVersion: '1.2.0',
                    updateUrl: updateUrl,
                    openUrl: openUrl,
                  );
                },
                child: const Text('open-update-dialog'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

void main() {
  testWidgets('发现新版本弹窗渲染标题/版本号对比/按钮', (tester) async {
    await tester.pumpWidget(await _host(openUrl: null));
    await tester.tap(find.text('open-update-dialog'));
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
    expect(find.textContaining('1.2.0'), findsOneWidget);
    expect(find.text('现在更新'), findsOneWidget);
    expect(find.text('以后再说'), findsOneWidget);
    // 不应该出现"忽略此版本"这类按钮——确认过参照项目里那是死代码。
    expect(find.text('忽略'), findsNothing);
  });

  testWidgets('点击"现在更新"触发外链跳转', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      await _host(
        openUrl: (url) async {
          calls.add(url);
        },
        updateUrl: 'https://example.com/download/v1.2.0',
      ),
    );
    await tester.tap(find.text('open-update-dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('现在更新'));
    await tester.pumpAndSettle();

    expect(calls, ['https://example.com/download/v1.2.0']);
  });

  testWidgets('点击"以后再说"只关闭弹窗，不触发跳转', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      await _host(
        openUrl: (url) async {
          calls.add(url);
        },
      ),
    );
    await tester.tap(find.text('open-update-dialog'));
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsOneWidget);

    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsNothing);
    expect(calls, isEmpty);
  });
}
