import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shortcuts_test_support.dart';

import '../../support/temp_dirs.dart';

/// Cmd+V 全局粘贴导入——剪贴板为空时必须给出明确的失败反馈，而不是静默无
/// 反应（用户按了快捷键会以为没生效）。单独一个文件的原因见
/// `desktop_shortcuts_test_support.dart` 头部文档。
void main() {
  testWidgets('剪贴板为空：给出明确提示，不调用 repo，不静默无反应', (tester) async {
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_empty_test_',
      );
      addTearDown(() async {
        await deleteTempDirBestEffort(tmpDir);
      });
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: const StubBoxService(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(const StubBoxService()),
          profileRepositoryProvider.overrideWith((_) => Future.value(repo)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);

      mockClipboard(tester); // text: null

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
      await pumpUntilFound(tester, find.textContaining('剪贴板为空'));

      expect(find.textContaining('剪贴板为空'), findsOneWidget);
      final profiles = await container.read(profileListProvider.future);
      expect(profiles, isEmpty);

      await drainToasts(tester);
    });
  });
}
