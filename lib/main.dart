import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/rule_set_provisioner.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/tray/tray_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';

const _sentryDsn = String.fromEnvironment('SENTRY_DSN');

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
        jsonEncode(
          getDefaultConfigOptions(
            executeConfigAsIs: modeIndex == 0,
            settings: container.read(networkSettingsProvider),
          ),
        ),
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
      titleBarStyle: Platform.isMacOS
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });

    // 桌面端系统托盘（macOS 状态栏 / Windows 任务栏 / Linux indicator）
    await TrayController.instance.setup(container);

    // 注册退出前钩子：用户关窗口时先停 sing-box，避免系统代理残留。
    await windowManager.setPreventClose(true);
    windowManager.addListener(_DesktopShutdownGuard(container));
  }

  // 启动时尝试自动更新所有订阅（按 updateInterval 判断哪些过期了）。
  // 失败不阻塞，让用户至少能用旧 profile。
  // ignore: discarded_futures
  _autoUpdateOnLaunch(container);

  // dev-only / CI smoke：检测 ~/.clashmiao_dev_subscription_url 或
  // CLASHMIAO_TEST_SUB_URL env，自动添加订阅 + 自动连接，解放手动 UI 测试。
  // Debug build 默认走；release build 只在显式 env 有 secret 时才触发（CI smoke）。
  final smokeEnv = Platform.environment['CLASHMIAO_TEST_SUB_URL'] ?? '';
  if (kDebugMode || smokeEnv.isNotEmpty) {
    // ignore: discarded_futures
    _devAutoBoot(container);
  }

  if (_sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.tracesSampleRate = 0.05;
        options.attachScreenshot = false;
        options.sendDefaultPii = false;
      },
      appRunner: () => runApp(
        UncontrolledProviderScope(
          container: container,
          child: const ClashMiaoApp(),
        ),
      ),
    );
  } else {
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const ClashMiaoApp(),
      ),
    );
  }
}

/// 桌面端关窗口时先停 sing-box，避免系统代理残留导致用户没网。
///
/// window_manager 的 `setPreventClose(true)` 让 onWindowClose 变成可拦截事件；
/// 我们 stop boxService 再 destroy。
class _DesktopShutdownGuard with WindowListener {
  _DesktopShutdownGuard(this._container);
  final ProviderContainer _container;
  bool _shuttingDown = false;

  @override
  void onWindowClose() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    try {
      await _container.read(connectionControllerProvider.notifier).disconnect();
    } catch (_) {
      // 即便停失败也得退，否则用户卡死
    }
    await TrayController.instance.dispose();
    await windowManager.destroy();
  }
}

/// 启动时按 `updateInterval` 自动更新过期的订阅。
///
/// `addByContent` 导入的本地节点（url 以 `content://` 开头）跳过 —— 它们
/// 没有可 fetch 的 HTTP URL。
Future<void> _autoUpdateOnLaunch(ProviderContainer container) async {
  try {
    final repo = await container.read(profileRepositoryProvider.future);
    final profiles = repo.getAll();
    final now = DateTime.now();
    for (final p in profiles) {
      if (p.url.startsWith('content://')) continue;
      final last = p.lastUpdate;
      if (last == null) continue;
      if (now.difference(last) < p.updateInterval) continue;
      try {
        debugPrint('[AutoUpdate] 更新 ${p.name}...');
        await repo.update(p.id);
      } catch (e) {
        debugPrint('[AutoUpdate] ${p.name} 更新失败: $e');
      }
    }
  } catch (e) {
    debugPrint('[AutoUpdate] 整体失败: $e');
  }
}

/// Dev-only：如果用户主目录有 `.clashmiao_dev_subscription_url`，
/// 自动添加订阅 + 自动连接，省去手动 UI 操作来跑调试循环。
Future<void> _devAutoBoot(ProviderContainer container) async {
  try {
    // 三种入口：
    //   1. CLASHMIAO_TEST_SUB_URL 环境变量（CI 注入 secret 走这条）
    //   2. ~/.clashmiao_dev_subscription_url 文件（unix dev 习惯）
    //   3. %USERPROFILE%\.clashmiao_dev_subscription_url（windows）
    final env = Platform.environment;
    String url = (env['CLASHMIAO_TEST_SUB_URL'] ?? '').trim();
    if (url.isEmpty) {
      final home = env['HOME'] ?? env['USERPROFILE'];
      if (home == null) return;
      final urlFile = File('$home/.clashmiao_dev_subscription_url');
      if (!await urlFile.exists()) return;
      url = (await urlFile.readAsString()).trim();
    }
    if (url.isEmpty) return;

    final repo = await container.read(profileRepositoryProvider.future);
    final existing = repo.getAll();
    if (existing.isEmpty) {
      debugPrint('[DevBoot] 自动添加订阅...');
      try {
        const proxyUriSchemes = [
          'ss',
          'vless',
          'vmess',
          'trojan',
          'hysteria',
          'hysteria2',
          'tuic',
        ];
        final isProxyUri = proxyUriSchemes.any((s) => url.startsWith('$s://'));
        if (isProxyUri) {
          await repo.addByContent(url, name: 'dev');
        } else {
          await repo.addByUrl(url, customName: 'dev');
        }
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
    await container.read(connectionControllerProvider.notifier).toggle();
  } catch (e, st) {
    debugPrint('[DevBoot] 出错: $e\n$st');
  }
}
