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

/// Cmd+V 全局粘贴导入——剪贴板是 http(s) 订阅链接时走 `addByUrl`。单独一个
/// 文件的原因见 `desktop_shortcuts_test_support.dart` 头部文档。
void main() {
  testWidgets('Cmd+V：剪贴板是 http(s) 订阅链接 → addByUrl 落地 + 成功 toast', (
    tester,
  ) async {
    // 这条真的会走一次本地 HttpServer 网络请求（ProfileRepository.addByUrl
    // 内部用 dio 实际 fetch），widget test 默认的 fake-time zone 里真实
    // Socket/IO 完成回调等不到（同 profile_details_page_save_test.dart 的
    // `_withRealNetwork` 写法），必须用 `tester.runAsync` 逃出去；
    // `TestWidgetsFlutterBinding` 全局装的 HTTP mock（一律返回 400）也要
    // 关掉，否则请求会被拦截。
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = null);

    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_url_test_',
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

      final server = await serveOnce(validSingBoxJsonBody);
      addTearDown(() => server.close(force: true));
      final subUrl = 'http://localhost:${server.port}/sub#我的订阅';
      mockClipboard(tester, text: subUrl);

      // 用真实 defaultPasteImport（走真实 Cmd+V → Shortcuts → Action 映射），
      // 但额外包一层 completer 拿到"这次调用真正 await 完"的精确信号——比
      // 按固定 Duration 轮询更稳，不依赖 runAsync/fake-time zone 边界的具体
      // 调度细节。
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
      await pumpUntilFound(tester, find.textContaining('已导入订阅'));

      expect(find.textContaining('已导入订阅'), findsOneWidget);
      final profiles = await container.read(profileListProvider.future);
      expect(profiles, hasLength(1));
      expect(profiles.single.url, subUrl);

      await drainToasts(tester);
    });
  });
}
