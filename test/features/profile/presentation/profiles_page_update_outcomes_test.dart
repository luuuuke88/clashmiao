import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:clashmiao/domain/profile/data/profile_store.dart';
import 'package:clashmiao/domain/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/scripted_profile_repository.dart';
import '../../../support/toast_pump.dart';

/// 订阅页面对仓库异常的反馈：
/// - 刷新结果因订阅被改动而作废（stale）：预期内的取消，静默；
/// - 存储只读：统一的本地化升级提示；
/// - 普通失败：照旧提示失败。
///
/// toast 断言放在同一个测试里按顺序做：先触发「只读」证明 toast 能渲染出来，
/// 再触发 stale，断言什么都没有弹出——否则「没弹出」可能只是 toast 没渲染。
const _profileA = ProfileEntity(
  id: 'profile-a',
  name: '订阅 A',
  url: 'https://example.com/a',
);
const _profileB = ProfileEntity(
  id: 'profile-b',
  name: '订阅 B',
  url: 'https://example.com/b',
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('刷新 / 切换 / 更新全部：只读给出升级提示，stale 静默，普通失败照旧', (tester) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      ProfileStore.profilesKey: jsonEncode([
        _profileA.toJson(),
        _profileB.toJson(),
      ]),
      ProfileStore.activeProfileKey: _profileA.id,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
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
            home: const ProfilesPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const upgrade = '请升级 App 后再修改订阅';
    // 页头「更新全部」是第一个同图标按钮，卡片上的单条刷新是其后的。
    final updateIcons = find.byIcon(FluentIcons.arrow_sync_24_regular);

    // 1. 单条刷新：只读 → 升级提示。
    repo.updateError = const StoreReadOnlyException(9);
    await tester.tap(updateIcons.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text(upgrade), findsOneWidget);
    await _drainToasts(tester);

    // 2. 单条刷新：stale → 什么提示都没有（既不失败，也不报成功）。
    repo.updateError = const ProfileUpdateStaleException('profile-a');
    await tester.tap(updateIcons.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.textContaining('失败'), findsNothing);
    expect(find.textContaining('成功'), findsNothing);
    expect(find.text(upgrade), findsNothing);
    await _drainToasts(tester);

    // 3. 单条刷新：普通失败 → 照旧提示失败，且不是升级提示。
    repo.updateError = Exception('network down');
    await tester.tap(updateIcons.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text('更新配置文件失败'), findsOneWidget);
    expect(find.textContaining('network down'), findsNothing, reason: '原文只进日志');
    expect(find.text(upgrade), findsNothing);
    await _drainToasts(tester);

    // 4. 切换激活订阅：只读 → 升级提示；普通失败 → 照旧提示。
    //    （AppToast 对同一文案 800ms 内去重，所以相邻两步文案必须不同。）
    repo.setActiveError = const StoreReadOnlyException(9);
    await tester.tap(find.text('订阅 B'));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text(upgrade), findsOneWidget);
    await _drainToasts(tester);

    repo.setActiveError = Exception('disk full');
    await tester.tap(find.text('订阅 B'));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text('切换配置文件失败'), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing, reason: '原文只进日志');
    await _drainToasts(tester);

    // 5. 更新全部：只读 → 升级提示（updateAll 会把只读异常抛出来）。
    repo.updateAllError = const StoreReadOnlyException(9);
    await tester.tap(updateIcons.first);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpToast(tester);
    expect(find.text(upgrade), findsOneWidget);
    await _drainToasts(tester);
  });

  testWidgets('刷新进行中页面被销毁，随后旧刷新作废（stale）：不抛异常', (tester) async {
    SharedPreferences.setMockInitialValues({
      'locale': 'zhCn',
      ProfileStore.profilesKey: jsonEncode([_profileA.toJson()]),
      ProfileStore.activeProfileKey: _profileA.id,
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = await scriptedRepository(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
        boxServiceProvider.overrideWithValue(const StubBoxService()),
        profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
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
            home: const ProfilesPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gate = Completer<void>();
    repo
      ..updateGate = gate
      ..updateError = const ProfileUpdateStaleException('profile-a');
    // 页头「更新全部」是第一个同图标按钮，卡片上的单条刷新是其后的。
    await tester.tap(find.byIcon(FluentIcons.arrow_sync_24_regular).at(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.updateCalls, 1, reason: '刷新已发出并卡住');

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
  });
}
