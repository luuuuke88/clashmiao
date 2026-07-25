import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shortcuts_test_support.dart';

import '../../support/temp_dirs.dart';

/// Cmd+V 全局粘贴导入——剪贴板内容不像有效订阅（native 校验失败）时必须给出
/// 明确的失败 toast，而不是静默成功或无反应。单独一个文件的原因见
/// `desktop_shortcuts_test_support.dart` 头部文档。
void main() {
  testWidgets('剪贴板内容不像有效订阅（native 校验失败）：明确的失败 toast', (tester) async {
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_failure_test_',
      );
      addTearDown(() async {
        await deleteTempDirBestEffort(tmpDir);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // 这条要用不特判 StubBoxService 的假 BoxService，见
      // RejectingBoxService 类文档：否则 ProfileRepository 会跳过 native
      // 校验，永远不会失败。
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: RejectingBoxService(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(RejectingBoxService()),
          profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);

      mockClipboard(tester, text: '这明显不是订阅内容也不是任何已知协议');

      final done = Completer<void>();
      await pumpShortcuts(
        tester,
        container: container,
        onPasteImport: (ref) async {
          await defaultPasteImport(ref);
          if (!done.isCompleted) done.complete();
        },
      );
      await pressPaste(tester, meta: true);
      await done.future.timeout(const Duration(seconds: 10));
      await pumpUntilFound(tester, find.textContaining('导入失败'));

      expect(find.textContaining('导入失败'), findsOneWidget);
      final profiles = await container.read(profileListProvider.future);
      expect(profiles, isEmpty);

      await drainToasts(tester);
    });
  });
}
