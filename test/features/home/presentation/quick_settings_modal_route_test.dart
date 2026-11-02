import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/features/home/presentation/quick_settings_modal.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  testWidgets('快速设置点「所有进阶选项」：配置选项页压在根 Navigator 上，返回后弹窗状态不变', (tester) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      'clashmiao_set_system_proxy': true,
      'clashmiao_enable_tun': false,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);

    NavigatorState? pushedOn;
    NavigatorState? root;
    final rootKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: AppRouteScope(
          builders: {
            AppRoute.configOptions: (context) {
              pushedOn = Navigator.of(context);
              root = Navigator.of(context, rootNavigator: true);
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('配置选项页桩'),
                  ),
                ),
              );
            },
          },
          child: ToastificationWrapper(
            child: MaterialApp(
              navigatorKey: rootKey,
              theme: ThemeData.light().copyWith(
                extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              ),
              // 快速设置放在一个嵌套 Navigator 里：不传 rootNavigator 的话
              // 页面会压到嵌套 Navigator，而不是根。
              home: Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: QuickSettingsModal()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 先改一个状态，用来验证返回后弹窗没有被重建/重置。
    await tester.tap(find.text('启用 TLS 数据分段'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.text('所有进阶选项'));
    await tester.pumpAndSettle();

    expect(find.text('配置选项页桩'), findsOneWidget);
    expect(pushedOn, isNotNull);
    expect(pushedOn, same(root), reason: '配置选项页必须压在根 Navigator 上');
    expect(root, same(rootKey.currentState));

    await tester.tap(find.text('配置选项页桩'));
    await tester.pumpAndSettle();

    expect(find.text('配置选项页桩'), findsNothing);
    expect(find.text('快速设置'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(container.read(networkSettingsProvider).enableTlsFragment, isTrue);
  });
}
