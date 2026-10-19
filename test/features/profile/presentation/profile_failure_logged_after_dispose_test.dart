import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
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
import '../../../support/temp_dirs.dart';

/// 页面销毁后操作才失败：界面反馈被 `mounted` 挡掉是对的，但技术详情不能跟着
/// 丢——catch 里先无条件写应用日志（用户可导出的 app.log），再看 `mounted`。
const _profileA = ProfileEntity(
  id: 'profile-a',
  name: '订阅 A',
  url: 'https://example.com/a',
);

void main() {
  late Directory tempDir;
  late File logFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('failure_log_test_');
    logFile = File('${tempDir.path}/app.log');
    AppLogger.configureForTesting(resolveLogFile: () async => logFile);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    AppLogger.resetForTesting();
    resetAppFailureDedupForTesting();
    await deleteTempDirBestEffort(tempDir);
  });

  testWidgets('刷新进行中页面被销毁，随后普通失败：不弹提示、不抛异常，但写进 app.log', (tester) async {
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
      ..updateError = Exception('upstream exploded after dispose');
    // 页头「更新全部」是第一个同图标按钮，卡片上的单条刷新是其后的。
    await tester.tap(find.byIcon(FluentIcons.arrow_sync_24_regular).at(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.updateCalls, 1, reason: '刷新已发出并卡住');

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('exploded'), findsNothing);

    // 日志写盘是真实文件 I/O，而写入是在 fake-time zone 里发起的：I/O 完成要
    // 逃出去等（runAsync），之后的续体是 fake zone 的微任务，要靠 pump 推进。
    // 两者交替推进，直到内容落地（不在 runAsync 里 await 写入本身，否则死锁）。
    var content = '';
    for (var i = 0; i < 200 && !content.contains('exploded'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      content =
          await tester.runAsync(
            () async =>
                await logFile.exists() ? await logFile.readAsString() : '',
          ) ??
          '';
    }
    expect(content, contains('[ERROR] profiles.update'));
    expect(content, contains('upstream exploded after dispose'));
  });
}
