import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/connection/application/connection_controller.dart';
import 'package:clashmiao/features/profile/application/profile_providers.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:clashmiao/shared/navigation/app_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/fake_connection_controller.dart';

const _marker = Key('profiles-route-stub');

Future<Widget> _host({
  required ProfileEntity? active,
  required List<ProfileEntity> profiles,
}) async {
  SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
  PackageInfo.setMockInitialValues(
    appName: 'ClashMiao',
    packageName: 'com.clashmiao.app',
    version: '1.2.3',
    buildNumber: '45',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      connectionControllerProvider.overrideWith(FakeConnectionController.new),
      activeProfileProvider.overrideWith((_) => Future.value(active)),
      profileListProvider.overrideWith((_) => Future.value(profiles)),
      outboundGroupsProvider.overrideWith(
        (_) => Stream<List<OutboundGroup>>.value(const []),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  await container.read(activeProfileProvider.future);
  await container.read(profileListProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: AppRouteScope(
      builders: {
        AppRoute.profiles: (_) => const SizedBox(key: _marker, height: 120),
      },
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
          ),
          home: const HomePage(),
        ),
      ),
    ),
  );
}

void main() {
  const active = ProfileEntity(
    id: 'p1',
    name: 'ClashMiao Pro',
    url: 'https://example.com/sub',
    active: true,
  );

  testWidgets('首页点订阅卡：经 AppRouteScope 在底部弹层里展开订阅页', (tester) async {
    await tester.pumpWidget(await _host(active: active, profiles: [active]));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(_marker), findsNothing);

    await tester.tap(find.text('ClashMiao Pro'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_marker), findsOneWidget);
    // 仍是底部弹层（模态底部面板），不是整页 push。
    expect(
      find.ancestor(
        of: find.byKey(_marker),
        matching: find.byType(BottomSheet),
      ),
      findsOneWidget,
    );
  });

  testWidgets('首页无激活订阅时点「配置文件」，同样经 AppRouteScope 展开订阅页', (tester) async {
    const other = ProfileEntity(
      id: 'p2',
      name: '备用配置',
      url: 'https://example.com/sub',
      active: false,
    );
    await tester.pumpWidget(await _host(active: null, profiles: [other]));
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('配置文件'));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(_marker), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(_marker),
        matching: find.byType(BottomSheet),
      ),
      findsOneWidget,
    );
  });
}
