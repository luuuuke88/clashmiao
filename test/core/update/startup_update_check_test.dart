import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/core/update/startup_update_check.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搭一个最小的 widget 树只是为了拿一个真实可用的 BuildContext——不需要
/// 挂 GoRouter/ShellPage 那一整套依赖，跟生产环境用
/// `appRouterNavigatorKey.currentContext` 的唯一差别只是 context 的来源，
/// [runStartupUpdateCheck] 本身不关心 context 是从哪儿来的。
Future<(ProviderContainer, BuildContext)> _harness(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);

  late BuildContext capturedContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
        ),
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const Scaffold();
          },
        ),
      ),
    ),
  );

  return (container, capturedContext);
}

void main() {
  testWidgets('发现新版本时弹出「发现新版本」对话框', (tester) async {
    final (container, context) = await _harness(tester);
    addTearDown(container.dispose);

    await runStartupUpdateCheck(
      container,
      initialDelay: Duration.zero,
      contextProvider: () => context,
      checkOnce: (prefs, {dio, mixedPort = 0}) async => 'v9.9.9',
    );
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsOneWidget);
    expect(find.textContaining('1.0.0'), findsOneWidget);
    expect(find.textContaining('9.9.9'), findsOneWidget);
  });

  testWidgets('没有新版本时什么都不做：不弹窗、无视觉噪音', (tester) async {
    final (container, context) = await _harness(tester);
    addTearDown(container.dispose);

    await runStartupUpdateCheck(
      container,
      initialDelay: Duration.zero,
      contextProvider: () => context,
      checkOnce: (prefs, {dio, mixedPort = 0}) async => null,
    );
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('checkOnce 抛异常时静默吞掉，不让 App 崩溃、不弹窗', (tester) async {
    final (container, context) = await _harness(tester);
    addTearDown(container.dispose);

    await runStartupUpdateCheck(
      container,
      initialDelay: Duration.zero,
      contextProvider: () => context,
      checkOnce: (prefs, {dio, mixedPort = 0}) async {
        throw Exception('boom');
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('有可用更新'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('GITHUB_REPO_SLUG 为空场景（当前 dart-define 就是空字符串）', () {
    test('UpdateChecker.checkOnce 优雅返回 null，不抛异常', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await expectLater(UpdateChecker.checkOnce(prefs), completion(isNull));
    });

    testWidgets('runStartupUpdateCheck 用真实 checkOnce 时也安全不崩溃、不弹窗', (
      tester,
    ) async {
      final (container, context) = await _harness(tester);
      addTearDown(container.dispose);

      // 不传 checkOnce —— 走真实的 UpdateChecker.checkOnce，
      // 当前测试环境 GITHUB_REPO_SLUG 为空，预期优雅返回、什么都不做。
      await runStartupUpdateCheck(
        container,
        initialDelay: Duration.zero,
        contextProvider: () => context,
      );
      await tester.pumpAndSettle();

      expect(find.text('有可用更新'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
