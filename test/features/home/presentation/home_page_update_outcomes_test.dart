import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/model/outbound.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/scripted_profile_repository.dart';

/// 首页的订阅刷新按钮：只读给出升级提示、刷新被取代（stale）静默、普通失败照旧。
const _profile = ProfileEntity(
  id: 'profile-1',
  name: '主订阅',
  url: 'https://example.com/sub',
  active: true,
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

void main() {
  testWidgets('首页刷新：只读 → 升级提示；stale → 静默；普通失败 → 失败提示', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    PackageInfo.setMockInitialValues(
      appName: 'ClashMiao',
      packageName: 'com.clashmiao.app',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        activeProfileProvider.overrideWith((_) => Future.value(_profile)),
        profileListProvider.overrideWith((_) => Future.value([_profile])),
        outboundGroupsProvider.overrideWith(
          (_) => Stream<List<OutboundGroup>>.value(const []),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(activeProfileProvider.future);
    await container.read(profileListProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
    await tester.pump(const Duration(milliseconds: 250));

    final refresh = find.byTooltip('更新配置文件');
    expect(refresh, findsOneWidget);

    repo.updateError = const StoreReadOnlyException(9);
    await tester.tap(refresh);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请升级 App 后再修改订阅'), findsOneWidget);
    await _drainToasts(tester);

    repo.updateError = const ProfileUpdateStaleException('profile-1');
    await tester.tap(refresh);
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.updateCalls, 2);
    expect(find.textContaining('失败'), findsNothing);
    expect(find.textContaining('成功'), findsNothing);
    expect(find.text('请升级 App 后再修改订阅'), findsNothing);
    await _drainToasts(tester);

    repo.updateError = Exception('network down');
    await tester.tap(refresh);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('更新配置文件失败'), findsOneWidget);
    await _drainToasts(tester);
  });
}
