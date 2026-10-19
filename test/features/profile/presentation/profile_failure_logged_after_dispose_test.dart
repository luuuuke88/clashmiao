import 'dart:async';
import 'dart:convert';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/localization/gen/translations.g.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/theme/theme_extensions.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
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

/// 页面销毁后操作才失败：界面反馈被 `mounted` 挡掉是对的，但技术详情不能跟着
/// 丢——catch 里先无条件写应用日志，再看 `mounted`。
///
/// 日志用测试接缝 [debugAppFailureSink] 接住（完成信号，不等真实写盘；写盘由
/// app_logger_test 覆盖）。应用与 Toast 宿主全程挂载，只拆掉订阅页面，所以
/// 「没有提示」是真的没有提示，而不是宿主没了。
const _profileA = ProfileEntity(
  id: 'profile-a',
  name: '订阅 A',
  url: 'https://example.com/a',
);

/// 失败提示的完整文案（zhCn）：`profileFailureMessage` 对普通异常给的就是它。
final _updateFailed = AppLocale.zhCn.build().profile.update.failureMsg;

Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 1000));
}

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

  testWidgets('刷新进行中只拆掉订阅页，随后普通失败：仍写应用日志，且没有失败提示', (tester) async {
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

    final showPage = ValueNotifier(true);
    addTearDown(showPage.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ToastificationWrapper(
          child: MaterialApp(
            theme: ThemeData.light().copyWith(
              extensions: <ThemeExtension<dynamic>>[AiUiTheme.light],
            ),
            home: ValueListenableBuilder<bool>(
              valueListenable: showPage,
              builder: (_, show, _) => show
                  ? const ProfilesPage()
                  : const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 页头「更新全部」是第一个同图标按钮，卡片上的单条刷新是其后的。
    final refreshButton = find.byIcon(FluentIcons.arrow_sync_24_regular).at(1);

    // 对照组：页面还在时同样的失败会弹出这条提示——证明宿主能渲染它，下面的
    // 「没有」才有意义。
    repo.updateError = Exception('boom while mounted');
    await tester.tap(refreshButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_updateFailed), findsOneWidget);
    expect(records.map((r) => r.where), ['profiles.update']);
    await _drainToasts(tester);
    expect(find.text(_updateFailed), findsNothing);
    records.clear();

    // 卡住刷新 → 只拆掉订阅页 → 放行，让它以普通失败结束。
    final gate = Completer<void>();
    final logged = Completer<AppFailureRecord>();
    debugAppFailureSink = (record) {
      records.add(record);
      if (!logged.isCompleted) logged.complete(record);
    };
    repo
      ..updateGate = gate
      ..updateError = Exception('upstream exploded after dispose');
    await tester.tap(refreshButton);
    await tester.pump();
    expect(repo.updateCalls, 2, reason: '第二次刷新已发出并卡住');

    showPage.value = false;
    await tester.pump();
    expect(find.byType(ProfilesPage), findsNothing, reason: '只有订阅页被拆掉');
    expect(find.byType(ToastificationWrapper), findsOneWidget);

    gate.complete();
    await tester.pump(); // 推进微任务：catch 在这里跑完
    expect(logged.isCompleted, isTrue, reason: '失败处理已结束，并已记录');
    final record = await logged.future;
    expect(record.where, 'profiles.update');
    expect(
      record.error.toString(),
      contains('upstream exploded after dispose'),
    );
    expect(record.stackTrace, isNotNull);
    expect(records, hasLength(1));

    // 失败处理已结束；再给提示足够的出现时间，确认它没有出现。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_updateFailed), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
