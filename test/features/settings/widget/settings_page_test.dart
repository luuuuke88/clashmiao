import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/settings/widget/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<Widget> _host() async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
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
        home: const SettingsPage(),
      ),
    ),
  );
}

void main() {
  group('SettingsPage smoke', () {
    testWidgets('页面整体渲染不崩 + 关键文字可见', (tester) async {
      await tester.pumpWidget(await _host());
      await tester.pump(const Duration(milliseconds: 200));

      // 顶部标题
      expect(find.text('设置'), findsOneWidget);
      // locale tile（zhCn）当前选择名
      expect(find.text('简体中文'), findsOneWidget);
      // 端口默认 2080
      expect(find.text('2080'), findsOneWidget);
      // 远程 DNS 默认 DoH（TCP 通道，兼容不支持 UDP 的代理节点）
      expect(find.text('https://1.1.1.1/dns-query'), findsOneWidget);
    });
  });
}
