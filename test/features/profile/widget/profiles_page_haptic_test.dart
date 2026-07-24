import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/widget/profiles_page.dart';
import 'package:dio/dio.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

/// 覆盖：wave4 触觉反馈扩展——订阅切换激活 / 订阅更新两个交互点。
///
/// 经核实，haptic 只挂在"切换激活订阅"（`selectActiveProfile`）和"更新单条
/// 订阅"（`UpdateProfile.updateProfile`）上，添加/删除订阅场景不加触觉反馈——
/// 所以这里不测、也不给添加/删除加调用，避免"凭空加"。
///
/// `update()` 会走真实 dio 网络请求，测试环境不应该真的发网络请求，所以用
/// 子类覆盖掉 `update()`（跟 `profiles_page_test.dart` 的
/// `_FakeWarpBoxService extends StubBoxService` 是同一个套路），只验证
/// "点击时触觉反馈是否被调用"，不关心订阅刷新的网络结果。
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository({required super.prefs})
    : super(
        dio: Dio(),
        configDir: Directory('/tmp/unused-haptic-profile-repo'),
        boxService: const StubBoxService(),
      );

  int updateCalls = 0;

  @override
  Future<ProfileEntity> update(String profileId) async {
    updateCalls++;
    return getAll().firstWhere((p) => p.id == profileId);
  }
}

const _profileA = ProfileEntity(
  id: 'profile-a',
  name: '订阅 A',
  url: 'https://example.com/a',
  active: true,
);
const _profileB = ProfileEntity(
  id: 'profile-b',
  name: '订阅 B',
  url: 'https://example.com/b',
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 300));
}

/// 平台通道在 pump 一个完整 MaterialApp 期间还会收到跟触觉反馈无关的调用
/// （比如 `SystemChrome.setApplicationSwitcherDescription`），不能直接断言
/// 整个 `calls` 列表为空，只筛出 `HapticFeedback.vibrate` 这一种方法。
Iterable<MethodCall> _hapticCalls(List<MethodCall> calls) =>
    calls.where((c) => c.method == 'HapticFeedback.vibrate');

Future<(Widget, _FakeProfileRepository)> _host({
  required List<ProfileEntity> profiles,
  bool hapticEnabled = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    'clashmiao_haptic_feedback': hapticEnabled,
    'clashmiao_profiles': jsonEncode(profiles.map((p) => p.toJson()).toList()),
    'clashmiao_active_profile': profiles.firstWhere((p) => p.active).id,
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = _FakeProfileRepository(prefs: prefs);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
    ],
  );
  await container.read(sharedPreferencesProvider.future);
  return (
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
    repo,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('切换激活订阅的触觉反馈', () {
    testWidgets('点击非激活订阅卡片切换为激活订阅触发轻度触觉反馈', (tester) async {
      final (widget, _) = await _host(profiles: [_profileA, _profileB]);
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('订阅 B'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        _hapticCalls(
          calls,
        ).where((c) => c.arguments == 'HapticFeedbackType.lightImpact'),
        hasLength(1),
      );
      await _drainToasts(tester);
    });

    testWidgets('触觉反馈偏好关闭时切换激活订阅不触发平台调用', (tester) async {
      final (widget, _) = await _host(
        profiles: [_profileA, _profileB],
        hapticEnabled: false,
      );
      await tester.pumpWidget(widget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('订阅 B'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_hapticCalls(calls), isEmpty);
      await _drainToasts(tester);
    });
  });

  group('更新订阅的触觉反馈', () {
    testWidgets('点击更新订阅按钮触发轻度触觉反馈', (tester) async {
      final (widget, repo) = await _host(profiles: [_profileA]);
      await tester.pumpWidget(widget);
      // 卡片入场有 fadeIn/slideX 动画，只 pump 固定时长有时会在动画中途截断
      // （更新图标的命中坐标落在视口外），pumpAndSettle 让动画完全跑完再操作，
      // 跟卡片本身的动画实现无关，纯粹是让测试稳定。
      await tester.pumpAndSettle();

      // 页头"更新全部"按钮跟卡片上的单条刷新按钮用的是同一个图标
      // （arrow_sync_24_regular），`.first` 命中的是页头（对应 `_updateAll`，
      // 经核实这个入口不加触觉反馈，见文件头注释）。这里只有一个远程订阅，
      // 卡片上的刷新图标是第二个匹配项，用 `.last` 精确指向它。
      await tester.tap(find.byIcon(FluentIcons.arrow_sync_24_regular).last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.updateCalls, 1);
      expect(
        _hapticCalls(
          calls,
        ).where((c) => c.arguments == 'HapticFeedbackType.lightImpact'),
        hasLength(1),
      );
      await _drainToasts(tester);
    });

    testWidgets('触觉反馈偏好关闭时点击更新订阅按钮不触发平台调用', (tester) async {
      final (widget, repo) = await _host(
        profiles: [_profileA],
        hapticEnabled: false,
      );
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();

      // 页头"更新全部"按钮跟卡片上的单条刷新按钮用的是同一个图标
      // （arrow_sync_24_regular），`.first` 命中的是页头（对应 `_updateAll`，
      // 经核实这个入口不加触觉反馈，见文件头注释）。这里只有一个远程订阅，
      // 卡片上的刷新图标是第二个匹配项，用 `.last` 精确指向它。
      await tester.tap(find.byIcon(FluentIcons.arrow_sync_24_regular).last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.updateCalls, 1);
      expect(_hapticCalls(calls), isEmpty);
      await _drainToasts(tester);
    });
  });
}
