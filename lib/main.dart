import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = ProviderContainer();
  // Ensure shared preferences are loaded before app runs
  await container.read(sharedPreferencesProvider.future);

  // 初始化 BoxService
  final boxService = container.read(boxServiceProvider);
  if (boxService is! StubBoxService) {
    try {
      await boxService.init();
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();
      final dirs = AppDirectories(
        baseDir: Directory(appDir.path),
        workingDir: Directory(appDir.path),
        tempDir: Directory(tempDir.path),
      );
      await boxService.setup(dirs, debug: true);

      // 传入默认配置（智能模式）
      await boxService.changeConfigOptions(
        jsonEncode(getDefaultConfigOptions()),
      );
      debugPrint('sing-box 核心初始化成功');
    } catch (e) {
      debugPrint('sing-box 初始化失败: $e');
    }
  } else {
    debugPrint('核心库未找到，使用桩实现');
  }

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowSize = Size(420, 850);
    WindowOptions windowOptions = WindowOptions(
      size: windowSize,
      minimumSize: windowSize,
      maximumSize: windowSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle:
          Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClashMiaoApp(),
    ),
  );
}
