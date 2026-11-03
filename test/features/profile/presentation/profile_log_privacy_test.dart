import 'dart:convert';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/features/profile/application/profile_providers.dart';
import 'package:clashmiao/features/profile/data/profile_store.dart';
import 'package:clashmiao/features/profile/model/profile_entity.dart';
import 'package:clashmiao/features/profile/presentation/profile_details_page.dart';
import 'package:clashmiao/features/profile/presentation/profile_form_dialog.dart';
import 'package:clashmiao/features/profile/presentation/profiles_page.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

import '../../../support/log_leak.dart';
import '../../../support/scripted_profile_repository.dart';

/// 界面层（订阅页 / 详情页 / 添加编辑入口）失败落盘时，异常里的订阅地址与节点
/// 地址不进持久日志；用户照常看到本地化的失败提示（提示文案由
/// `profileFailureMessage` 映射，不受影响）。
const _profile = ProfileEntity(
  id: 'p1',
  name: '订阅 A',
  url: 'https://example.com/a',
);

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

Future<ProviderContainer> _container(
  WidgetTester tester,
  ScriptedProfileRepository Function(SharedPreferences) makeRepo,
  void Function(ScriptedProfileRepository) onRepo,
) async {
  SharedPreferences.setMockInitialValues({
    'locale': 'zhCn',
    ProfileStore.profilesKey: jsonEncode([_profile.toJson()]),
    ProfileStore.activeProfileKey: _profile.id,
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = makeRepo(prefs);
  onRepo(repo);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
      boxServiceProvider.overrideWithValue(const StubBoxService()),
      profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sharedPreferencesProvider.future);
  return container;
}

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: ToastificationWrapper(
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            splashFactory: NoSplash.splashFactory,
          ),
          home: home,
        ),
      ),
    );

void main() {
  late List<AppFailureRecord> records;

  setUp(() {
    records = [];
    debugAppFailureSink = records.add;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    debugAppFailureSink = null;
    resetAppFailureDedupForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('订阅页：刷新 / 全部更新失败（普通异常与校验异常）不落订阅地址与节点地址', (tester) async {
    late ScriptedProfileRepository repo;
    final container = await _container(
      tester,
      (prefs) => repo = ScriptedProfileRepository(prefs: prefs),
      (_) {},
    );
    await tester.pumpWidget(_app(container, const ProfilesPage()));
    await tester.pumpAndSettle();
    final refreshIcon = find.byIcon(FluentIcons.arrow_sync_24_regular);

    repo.updateError = leakyException();
    await tester.tap(refreshIcon.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profiles.update']);
    expectNoLeak(records);
    await _drainToasts(tester);
    records.clear();

    repo.updateError = leakyValidation();
    await tester.tap(refreshIcon.at(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profiles.update']);
    expectNoLeak(records);
    expect(
      records.single.line,
      contains('ProfileValidationException(code=uri-invalid)'),
    );
    await _drainToasts(tester);
    records.clear();

    repo.updateAllError = leakyException();
    await tester.tap(refreshIcon.at(0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profiles.updateAll']);
    expectNoLeak(records);
    await _drainToasts(tester);
  });

  testWidgets('订阅页：列表加载失败的错误分支（含重建去重）不落原文', (tester) async {
    final container = await _container(
      tester,
      (prefs) => ScriptedProfileRepository(prefs: prefs),
      (_) {},
    );
    final erroring = ProviderContainer(
      parent: container,
      overrides: [
        profileListProvider.overrideWith((_) => throw leakyException()),
      ],
    );
    addTearDown(erroring.dispose);
    await tester.pumpWidget(_app(erroring, const ProfilesPage()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), contains('profiles.list'));
    expectNoLeak(records);
  });

  testWidgets('添加 / 编辑入口：校验异常与普通异常不落原文', (tester) async {
    late ScriptedProfileRepository repo;
    final container = await _container(
      tester,
      (prefs) => repo = ScriptedProfileRepository(prefs: prefs),
      (_) {},
    );
    late Future<void> Function() add;
    late Future<void> Function() edit;
    await tester.pumpWidget(
      _app(
        container,
        Consumer(
          builder: (context, ref, _) {
            add = () => doAddProfile(context, ref, 'ss://abc@h:1#x');
            edit = () => doEditProfile(context, ref, 'p1', name: '新名字');
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    repo.addError = leakyValidation();
    await add();
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profiles.add']);
    expectNoLeak(records);
    await _drainToasts(tester);
    records.clear();

    repo.editError = leakyException();
    await edit();
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profiles.edit']);
    expectNoLeak(records);
    await _drainToasts(tester);
  });

  testWidgets('详情页：保存失败（编辑 / 再拉取）不落原文', (tester) async {
    late ScriptedProfileRepository repo;
    final container = await _container(
      tester,
      (prefs) => repo = ScriptedProfileRepository(prefs: prefs),
      (_) {},
    );
    await tester.pumpWidget(_app(container, ProfileDetailsPage(_profile.id)));
    await tester.pump(const Duration(milliseconds: 250));
    final urlField = find.byWidgetPredicate(
      (w) => w is TextField && w.keyboardType == TextInputType.url,
    );
    await tester.enterText(urlField, 'https://new.example.invalid/new');

    repo.editError = leakyException();
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profileDetails.save']);
    expectNoLeak(records);
    await _drainToasts(tester);
    records.clear();

    repo
      ..editError = null
      ..updateError = leakyValidation();
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(records.map((r) => r.where), ['profileDetails.save']);
    expectNoLeak(records);
    await _drainToasts(tester);
  });
}
