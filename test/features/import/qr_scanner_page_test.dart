import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/features/import/qr_scanner_page.dart';
import 'package:flutter/material.dart';
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
  testWidgets('QrScannerPage renders permission denied state', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _host(
        const QrScannerPage(initialPermissionStatus: PermissionStatus.denied),
      ),
    );
    await tester.pump();

    expect(find.text('权限不足'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
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
