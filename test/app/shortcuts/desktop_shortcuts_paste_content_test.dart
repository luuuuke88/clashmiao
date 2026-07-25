import 'dart:async';
import 'dart:io';

import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_shortcuts_test_support.dart';

import '../../support/temp_dirs.dart';

/// Ctrl+V 全局粘贴导入——剪贴板是单节点代理 URI 时走 `addByContent`（不发起
/// 网络请求）。单独一个文件的原因见
/// `desktop_shortcuts_test_support.dart` 头部文档。
void main() {
  testWidgets('Ctrl+V（Windows/Linux）：剪贴板是单节点 URI → addByContent 落地', (
    tester,
  ) async {
    // 不需要网络，但 addByContent 内部仍有真实文件 I/O（写归一化后的配置
    // 文件），同样得用 runAsync 逃出 fake-time zone。
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_content_test_',
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

      const proxyUri =
          'vless://11111111-2222-3333-4444-555555555555'
          '@127.0.0.1:1?encryption=none#测试节点';
      mockClipboard(tester, text: proxyUri);

      final done = Completer<void>();
      await pumpShortcuts(
        tester,
        container: container,
        onPasteImport: (ref) async {
          await defaultPasteImport(ref);
          if (!done.isCompleted) done.complete();
        },
      );
      await pressPaste(tester, meta: false);
      await done.future.timeout(const Duration(seconds: 10));
      await pumpUntilFound(tester, find.textContaining('已导入订阅'));

      expect(find.textContaining('已导入订阅'), findsOneWidget);
      final profiles = await container.read(profileListProvider.future);
      expect(profiles, hasLength(1));
      expect(profiles.single.url, startsWith('content://'));

      await drainToasts(tester);
    });
  });
}
