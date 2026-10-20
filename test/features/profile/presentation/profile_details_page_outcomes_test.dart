import 'dart:async';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/presentation/profile_details_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/scripted_profile_repository.dart';

/// 详情页保存 / 手动刷新对仓库异常的反馈（见 profiles_page_update_outcomes_test.dart
/// 的说明：同一测试内先让 toast 出现、再断言「静默」）。
final _profile = ProfileEntity(
  id: 'p1',
  name: '旧订阅',
  url: 'https://old.example.invalid/sub',
  active: true,
  lastUpdate: DateTime.utc(2026, 1, 1),
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

void main() {
  testWidgets('保存：只读给出升级提示；保存后的再拉取被取代（stale）不算失败', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        profileListProvider.overrideWith((_) => Future.value([_profile])),
        activeProfileProvider.overrideWith((_) => Future.value(_profile)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              splashFactory: NoSplash.splashFactory,
            ),
            home: ProfileDetailsPage(_profile.id),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final urlField = find.byWidgetPredicate(
      (w) => w is TextField && w.keyboardType == TextInputType.url,
    );
    await tester.enterText(urlField, 'https://new.example.invalid/new');

    // 1. 只读：编辑被拒 → 升级提示。
    repo.editError = const StoreReadOnlyException(9);
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('请升级 App 后再修改订阅'), findsOneWidget);
    expect(repo.updateCalls, 0);
    await _drainToasts(tester);

    // 2. 编辑成功，但紧随其后的再拉取被取代：保存本身成功，不提示失败。
    repo.editError = null;
    repo.updateError = const ProfileUpdateStaleException('p1');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.updateCalls, 1);
    expect(find.text('配置文件保存成功'), findsOneWidget);
    expect(find.textContaining('失败'), findsNothing);
    await _drainToasts(tester);

    // 3. 再拉取真的失败：照旧明确提示。
    repo.updateError = Exception('network down');
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('配置文件保存失败'), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('手动刷新进行中页面被销毁，随后旧刷新作废（stale）：不抛异常', (tester) async {
    // 够高的视口，「立即更新」不会落在懒加载列表的屏幕之外。
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 「立即更新」只在远程且已取到流量信息的订阅上出现。
    final profile = _profile.copyWith(
      subInfo: const SubscriptionInfo(upload: 0, download: 0, total: 100),
    );
    SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        profileListProvider.overrideWith((_) => Future.value([profile])),
        activeProfileProvider.overrideWith((_) => Future.value(profile)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sharedPreferencesProvider.future);
    await container.read(profileListProvider.future);
    await container.read(activeProfileProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
              splashFactory: NoSplash.splashFactory,
            ),
            home: ProfileDetailsPage(_profile.id),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final gate = Completer<void>();
    repo
      ..updateGate = gate
      ..updateError = const ProfileUpdateStaleException('p1');
    await tester.tap(find.text('立即更新'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.updateCalls, 1, reason: '刷新已发出并卡住');

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
