import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/rule_set_provisioner.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:flutter/foundation.dart';
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

      // 把 bundled .srs rule-set 文件 provision 到 workingDir，
      // smart 模式的 RuntimeConfigBuilder 引用相对路径 ./geoip-cn.srs / ./geosite-cn.srs。
      await RuleSetProvisioner().ensureProvisioned(dirs.workingDir);

      // 启动时按 prefs 里持久化的 mode 推 changeConfigOptions
      // （之前默认 false，导致用户切到全局后被启动覆盖回 cn）。
      final prefs = container.read(sharedPreferencesProvider).requireValue;
      final modeIndex = prefs.getInt('clashmiao_proxy_mode') ?? 1; // 0=全局 1=智能
      await boxService.changeConfigOptions(
        jsonEncode(getDefaultConfigOptions(executeConfigAsIs: modeIndex == 0)),
      );
      debugPrint('sing-box 核心初始化成功（mode=$modeIndex）');
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

  // dev-only：检测 ~/.clashmiao_dev_subscription_url，自动添加订阅 + 自动连接，
  // 解放手动 UI 测试。release build 不会走这分支。
  if (kDebugMode) {
    // ignore: discarded_futures
    _devAutoBoot(container);
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const ClashMiaoApp(),
    ),
  );
}

/// Dev-only：如果用户主目录有 `.clashmiao_dev_subscription_url`，
/// 自动添加订阅 + 自动连接，省去手动 UI 操作来跑调试循环。
Future<void> _devAutoBoot(ProviderContainer container) async {
  try {
    final home = Platform.environment['HOME'];
    if (home == null) return;
    final urlFile = File('$home/.clashmiao_dev_subscription_url');
    if (!await urlFile.exists()) return;
    final url = (await urlFile.readAsString()).trim();
    if (url.isEmpty) return;

    final repo = await container.read(profileRepositoryProvider.future);
    final existing = repo.getAll();
    if (existing.isEmpty) {
      debugPrint('[DevBoot] 自动添加订阅...');
      try {
        await repo.addByUrl(url, customName: 'dev');
        debugPrint('[DevBoot] 订阅添加成功');
      } catch (e) {
        debugPrint('[DevBoot] 订阅添加失败: $e');
        return;
      }
    } else {
      debugPrint('[DevBoot] 已有订阅 ${existing.length} 个，跳过添加');
    }

    // 给 UI / status stream 一点时间稳定，然后触发 connect
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('[DevBoot] 自动连接...');
    await container
        .read(connectionControllerProvider.notifier)
        .toggle();
  } catch (e, st) {
    debugPrint('[DevBoot] 出错: $e\n$st');
  }
}
