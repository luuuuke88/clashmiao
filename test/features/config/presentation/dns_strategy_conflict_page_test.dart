import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/config/application/network_settings.dart';
import 'package:clashmiao/features/config/presentation/config_options_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Map<String, Object> stored,
) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn', ...stored});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const ConfigOptionsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('已存设置里的冲突：页首显示已重置的提示，确认后消失', (tester) async {
    final container = await _pump(tester, {
      'clashmiao_remote_dns_domain_strategy': 'ipv6_only',
    });

    expect(container.read(networkSettingsProvider).remoteDnsDomainStrategy, '');
    expect(find.textContaining('已重置为自动'), findsOneWidget);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已重置为自动'), findsNothing);
    expect(
      container.read(networkSettingsProvider.notifier).normalizationNotice,
      isEmpty,
    );
  });

  testWidgets('IPv6 禁用时选「仅 IPv6」：不生效，就地显示说明', (tester) async {
    final container = await _pump(tester, {});

    await tester.scrollUntilVisible(find.text('远程 DNS 域名策略'), 600);
    await tester.pumpAndSettle();
    await tester.tap(find.text('远程 DNS 域名策略'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ipv6_only'));
    await tester.pumpAndSettle();

    expect(container.read(networkSettingsProvider).remoteDnsDomainStrategy, '');
    await _drainToasts(tester);
    // toast 散去之后，页首的常驻提示仍在（不是一闪而过）。
    expect(find.textContaining('IPv6 路由已禁用'), findsOneWidget);
  });
}
