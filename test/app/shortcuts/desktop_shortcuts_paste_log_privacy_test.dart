import 'dart:async';
import 'dart:io';

import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/storage/shared_preferences_provider.dart';
import 'package:clashmiao/features/profile/application/profile_providers.dart';
import 'package:clashmiao/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/log_leak.dart';
import '../../support/temp_dirs.dart';
import 'desktop_shortcuts_test_support.dart';

/// native 解析器的拒绝原因会拼进订阅地址 / 节点地址（带稳定码）：Cmd+V 粘贴导入
/// 失败时，持久日志里不能出现它们，用户仍看到失败 toast。
class _LeakyRejectingBoxService extends RejectingBoxService {
  @override
  Future<String?> validateConfig(
    String path,
    String tempPath, {
    bool debug = false,
  }) async => 'uri-invalid: $leakMessage';
}

void main() {
  testWidgets('粘贴导入失败：持久日志不含订阅地址与节点地址', (tester) async {
    final records = <AppFailureRecord>[];
    debugAppFailureSink = records.add;
    addTearDown(() => debugAppFailureSink = null);
    await tester.runAsync(() async {
      final tmpDir = await Directory.systemTemp.createTemp(
        'desktop_shortcuts_paste_privacy_test_',
      );
      addTearDown(() async {
        await deleteTempDirBestEffort(tmpDir);
      });
      SharedPreferences.setMockInitialValues({'locale': 'zhCn'});
      final prefs = await SharedPreferences.getInstance();
      final box = _LeakyRejectingBoxService();
      final repo = ProfileRepository(
        dio: Dio(),
        configDir: tmpDir,
        prefs: prefs,
        boxService: box,
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith((_) => Future.value(prefs)),
          boxServiceProvider.overrideWithValue(box),
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
      await pumpUntilFound(tester, find.textContaining('添加配置文件失败'));

      expect(find.textContaining('添加配置文件失败'), findsOneWidget);
      expect(records.map((r) => r.where), contains('pasteImport.import'));
      expectNoLeak(records.where((r) => r.where == 'pasteImport.import'));

      await drainToasts(tester);
    });
  });
}
