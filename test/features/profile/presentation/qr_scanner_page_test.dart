import 'dart:async';

import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/shared/components/system_ui.dart';
import 'package:clashmiao/features/profile/presentation/qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _host(Widget child) async {
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
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('QrScannerPage renders permission denied state', (tester) async {
    await tester.pumpWidget(
      await _host(
        const QrScannerPage(initialPermissionStatus: PermissionStatus.denied),
      ),
    );
    await tester.pump();

    expect(find.text('权限不足'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  group('系统栏（浅色主题）', () {
    /// 记录最近一次下发给系统的导航栏 / 状态栏图标明暗。
    ({String? nav, String? status}) lastIcons(List<MethodCall> calls) {
      String? nav;
      String? status;
      for (final c in calls) {
        if (c.method != 'SystemChrome.setSystemUIOverlayStyle') continue;
        final args = c.arguments as Map<Object?, Object?>;
        nav = (args['systemNavigationBarIconBrightness'] as String?) ?? nav;
        status = (args['statusBarIconBrightness'] as String?) ?? status;
      }
      return (nav: nav, status: status);
    }

    testWidgets('进入扫码页：导航栏与状态栏图标变浅；退出后回到主题映射（浅色主题 = 深色图标）', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        ],
      );
      await container.read(sharedPreferencesProvider.future);

      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            themeMode: ThemeMode.light,
            theme: ThemeData.light(),
            builder: (context, child) => SystemUiScope(child: child!),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(lastIcons(calls).nav, 'Brightness.dark', reason: '浅色主题的全局映射');

      calls.clear();
      unawaited(
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const QrScannerPage(
              skipPermissionCheck: true,
              initialPermissionStatus: PermissionStatus.granted,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(lastIcons(calls).nav, 'Brightness.light', reason: '黑底上要浅色导航图标');
      expect(
        lastIcons(calls).status,
        'Brightness.light',
        reason: '黑底上要浅色状态栏图标',
      );

      calls.clear();
      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(lastIcons(calls).nav, 'Brightness.dark', reason: '退出后恢复全局映射');
      expect(lastIcons(calls).status, 'Brightness.dark');
    });
  });

  test('ScannerOverlay repaints when scan window changes', () {
    final painter = ScannerOverlay(const Rect.fromLTWH(10, 10, 100, 100));

    expect(
      painter.shouldRepaint(
        ScannerOverlay(const Rect.fromLTWH(10, 10, 100, 100)),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        ScannerOverlay(const Rect.fromLTWH(20, 20, 120, 120)),
      ),
      isTrue,
    );
  });
}
