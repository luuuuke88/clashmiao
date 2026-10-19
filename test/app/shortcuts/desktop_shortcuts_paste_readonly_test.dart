import 'dart:async';
import 'dart:io';

import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/core/storage/storage_schema.dart';
import 'package:clashmiao/domain/profile/application/profile_providers.dart';
import 'package:clashmiao/domain/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/temp_dirs.dart';
import 'desktop_shortcuts_test_support.dart';

/// Cmd+V 粘贴导入遇到存储只读（用户降级运行）：给本地化的升级提示，
/// 而不是异常原文。单独一个文件的原因见 `desktop_shortcuts_test_support.dart`。
void main() {
  testWidgets('存储只读时粘贴导入提示升级 App', (tester) async {
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_readonly_test_',
      );
      addTearDown(() async {
        await deleteTempDirBestEffort(tmpDir);
      });
      SharedPreferences.setMockInitialValues({
        'locale': 'zhCn',
        kStorageSchemaKey: kCurrentStorageSchema + 1,
      });
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

      mockClipboard(
        tester,
        text: 'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpwYXNz@h:443#n',
      );

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
      await pumpUntilFound(tester, find.text('请升级 App 后再修改订阅'));

      expect(find.text('请升级 App 后再修改订阅'), findsOneWidget);
      expect(find.textContaining('导入失败'), findsNothing);
      expect(repo.getAll(), isEmpty);

      await drainToasts(tester);
    });
  });
}
