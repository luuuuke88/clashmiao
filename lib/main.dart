import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clashmiao/core/config/build_config.dart';
import 'package:clashmiao/app/app.dart';
import 'package:clashmiao/core/box_service/box_providers.dart';
import 'package:clashmiao/core/box_service/stub_box_service.dart';
import 'package:clashmiao/core/config/default_config_options.dart';
import 'package:clashmiao/core/deep_link/deep_link_service.dart';
import 'package:clashmiao/core/health/connection_health_monitor.dart';
import 'package:clashmiao/core/logger/app_logger.dart';
import 'package:clashmiao/core/model/directories.dart';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/proxy/system_proxy_guard.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/app/shortcuts/desktop_shortcuts.dart';
import 'package:clashmiao/app/tray/tray_controller.dart';
import 'package:clashmiao/app/update/startup_update_check.dart';
import 'package:clashmiao/app/window/desktop_exit_guard.dart';
import 'package:clashmiao/core/window/silent_start.dart';
import 'package:clashmiao/features/profile/state/profiles_update_scheduler.dart';
import 'package:clashmiao/shared/components/profile_form_dialog.dart'
    show isHttpDownloadUrl;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// 见 `core/config/build_config.dart`：所有编译期参数集中声明在那里。
const _sentryDsn = sentryDsn;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App 层日志基础设施：FlutterError.onError / PlatformDispatcher.onError
  // 兜底捕获写入本地 app.log，纯本地文件、不涉及上报，不受下面"数据分析"
  // 开关影响——任何情况下都该记录，方便排障。必须尽早调用，尽量少漏掉
  // 启动过程中的异常。
  await initAppLogger();

  final container = ProviderContainer();
  // Ensure shared preferences are loaded before app runs
  await container.read(sharedPreferencesProvider.future);

  // 初始化 BoxService
  final boxService = container.read(boxServiceProvider);
  if (boxService is! StubBoxService) {
    try {
      await boxService.init();
      // iOS 上 sing-box 运行时文件必须落在 App Group 共享容器（Runner 和
      // packet-tunnel extension 是两个独立沙盒进程，只有共享容器两边都能
      // 访问），其它平台维持原来的 path_provider Documents 目录不变——
      // 详见 resolveSingBoxWorkingDirectory 的文档。
      final appDir = await resolveSingBoxWorkingDirectory();
      final tempDir = await getTemporaryDirectory();
      final dirs = AppDirectories(
        baseDir: Directory(appDir.path),
        workingDir: Directory(appDir.path),
        tempDir: Directory(tempDir.path),
      );
      await boxService.setup(dirs, debug: true);

      // 启动时按 prefs 里持久化的 mode 推 changeConfigOptions
      // （之前默认 false，导致用户切到全局后被启动覆盖回 cn）。
      final prefs = container.read(sharedPreferencesProvider).requireValue;
      final modeIndex = prefs.getInt('clashmiao_proxy_mode') ?? 1; // 0=全局 1=智能
      await boxService.changeConfigOptions(
        jsonEncode(
          getDefaultConfigOptions(
            executeConfigAsIs: modeIndex == 0,
            isSmart: modeIndex != 0,
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
      // 静默启动（设置页 clashmiao_silent_start 开关）：跳过 show()/focus()
      // 让窗口保持初始隐藏状态，而不是"先 show 再 hide"避免闪烁。
      await showWindowUnlessSilentStart(
        container.read(sharedPreferencesProvider).requireValue,
      );
      await windowManager.setResizable(false);
    });

    // 桌面端系统托盘（macOS 状态栏 / Windows 任务栏 / Linux indicator）
    await TrayController.instance.setup(container);

    // 注册关窗口钩子：点击窗口关闭按钮只隐藏到托盘，不断开 VPN、不退出进程
    // （真正退出走托盘菜单"退出"项，见 TrayController.onTrayMenuItemClick）。
    await windowManager.setPreventClose(true);
    windowManager.addListener(DesktopShutdownGuard());

    // 退出守卫：操作系统请求终止我们时（macOS 的 Cmd+Q / 菜单退出、Windows 与
    // Linux 的注销/关机），先停内核**还原系统代理**、清托盘，再放行退出。
    //
    // 不装的话，Cmd+Q 会直接终止进程、Dart 侧一行清理都跑不到——而桌面端默认
    // 开着 set-system-proxy，那是写进系统的持久化设置，只在优雅关闭时还原。
    // 结果就是按一下 Cmd+Q，系统代理永久指向一个已经没人监听的本地端口，整机
    // 浏览器都打不开网页（详见 DesktopExitGuard 的类文档）。
    DesktopExitGuard(container).install();

    // 自愈上一次**异常退出**（崩溃 / 强制退出 / 断电）残留的系统代理。
    //
    // 上面那个 Cmd+Q 的钩子只能覆盖"操作系统给了清理机会"的情形；被强杀时
    // 谁都拦不住，而三个桌面平台的系统代理写的都是持久化设置，残留后会让
    // 整机的浏览器都打不开网页，同时 App 界面显示"未连接"——两个信息互相
    // 矛盾，用户几乎不可能自己定位到是代理设置残留（详见
    // core/proxy/system_proxy_guard.dart）。
    //
    // 不 await：它要跑几条外部命令，不该阻塞启动。而且只有在上次确实置了
    // 脏标记时才会真的去查，绝大多数启动直接返回。
    unawaited(
      healStaleSystemProxyIfNeeded(
        prefs: container.read(sharedPreferencesProvider).requireValue,
        expectedPort: container.read(networkSettingsProvider).mixedPort,
      ).then((result) {
        if (result.healedAnything) {
          // 清理掉了就要告诉用户。不然他们只知道"刚才网不通、现在又好了"，
          // 下次再遇到还是一样懵。
          container.read(staleProxyHealedNoticeProvider.notifier).state =
              result.healedScopes;
        }
      }),
    );
  }

  // 深链导入：监听 sing-box:// clash:// clashmeta:// clashmiao:// 链接
  // （AndroidManifest.xml 已注册好 intent-filter，点击这类链接能拉起 App）。
  // 尽早 read 一次触发 DeepLinkService 创建——它在创建时自己发起监听
  // （不 await，不阻塞这里；解析/导入结果由 ShellPage 监听后弹 toast）。
  container.read(deepLinkServiceProvider);

  // 连接健康探测（"已连接但实际不通"的黑洞检测）。周期探测只由这里显式激活，
  // 不会因为首页 watch 了这个 provider 就自动开始——探测该活多久取决于 App，
  // 不取决于某个页面在不在（详见 ConnectionHealthMonitor 类文档）。
  container.read(connectionHealthProvider.notifier).start();

  // 订阅自动更新调度器：读每条订阅的 updateInterval，到期的用跟"立即更新"
  // 按钮同一条刷新逻辑静默更新一次。触发时机三条：这里的启动时查一次
  // （失败不阻塞，让用户至少能用旧 profile）、Timer.periodic 定期查一次、
  // App 从后台恢复前台时再查一次（详见 ProfileUpdateScheduler 类文档）。
  final profileUpdateScheduler = ProfileUpdateScheduler(
    repositoryProvider: () => container.read(profileRepositoryProvider.future),
    onChecked: (_) {
      container.invalidate(profileListProvider);
      container.invalidate(activeProfileProvider);
    },
  );
  unawaited(profileUpdateScheduler.checkAndRefreshDue());
  profileUpdateScheduler.start();

  // 启动静默自动检查更新：检查到新版本才弹「发现新版本」对话框（见
  // core/update/startup_update_check.dart），没有新版本 / 网络失败 /
  // GITHUB_REPO_SLUG 为空时什么都不做，不产生任何视觉噪音。跟上面订阅的
  // 自动更新调度器、跟关于页手动点「检查更新」都相互独立，谁都不依赖谁。
  unawaited(runStartupUpdateCheck(container));

  // dev-only / CI smoke：检测 ~/.clashmiao_dev_subscription_url 或
  // CLASHMIAO_TEST_SUB_URL env，自动添加订阅 + 自动连接，解放手动 UI 测试。
  // Debug build 默认走；release build 只在显式 env 有 secret 时才触发（CI smoke）。
  const smokeDefine = String.fromEnvironment('CLASHMIAO_TEST_SUB_URL');
  final smokeEnv = smokeDefine.isNotEmpty
      ? smokeDefine
      : Platform.environment['CLASHMIAO_TEST_SUB_URL'] ?? '';
  if (kDebugMode || smokeEnv.isNotEmpty) {
    unawaited(_devAutoBoot(container));
  }

  // 数据分析开关（'clashmiao_analytics_enabled'，onboarding/settings 页共用同
  // 一个 key，默认 false，opt-in——clashmiao 有意比参照项目更保守，这是既定
  // 产品决策）决定 Sentry SDK 要不要真的初始化：之前只要编译期 SENTRY_DSN
  // 非空就无条件 init，关掉开关后未处理异常/原生崩溃依然被自动上报，隐私
  // 承诺和实际行为不符。prefs 在 main() 顶部已经 await 过 sharedPreferencesProvider.future，
  // 这里读的是同一个已经 resolve 的值，requireValue 不会抛。
  final analyticsEnabled =
      container
          .read(sharedPreferencesProvider)
          .requireValue
          .getBool('clashmiao_analytics_enabled') ??
      false;

  await bootstrapSentryGatedApp(
    dsn: _sentryDsn,
    analyticsEnabled: analyticsEnabled,
    initSentry: (dsn, appRunner) => SentryFlutter.init((options) {
      options.dsn = dsn;
      options.tracesSampleRate = 0.05;
      options.attachScreenshot = false;
      options.sendDefaultPii = false;
    }, appRunner: appRunner),
    // 桌面端全局键盘快捷键（Cmd/Ctrl+V 快速粘贴导入订阅是最高优先级的一个，
    // 另外还有 macOS 的 Cmd+W/Cmd+,、Linux 的 Ctrl+Q，见
    // core/shortcuts/desktop_shortcuts.dart 的文档）。必须包在
    // `ClashMiaoApp`（内含 `MaterialApp.router`）外面——Flutter 处理键盘事件
    // 时从聚焦节点往上找最近的 Shortcuts 祖先，文本框自身的复制/粘贴快捷键
    // 由框架内置的 DefaultTextEditingShortcuts 提供（嵌在 MaterialApp 内部，
    // 比这里更靠近文本框），会先一步命中，不会被这里的全局粘贴导入吞掉。
    // 移动端不需要全局快捷键，维持原来直接 runApp(ClashMiaoApp()) 的行为。
    appRunner: () => runApp(
      UncontrolledProviderScope(
        container: container,
        child: (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            ? const DesktopShortcutsWrapper(child: ClashMiaoApp())
            : const ClashMiaoApp(),
      ),
    ),
  );
}

/// Sentry SDK 初始化门控：只有编译期 `SENTRY_DSN` 非空 **且** 用户勾选了
/// "数据分析"开关时才真正调用 [initSentry]；否则只跑 [appRunner]，SDK 完全
/// 不会被初始化（连自动捕获未处理异常/原生崩溃的能力都不会挂载）。
///
/// 抽成可注入 [initSentry] / [appRunner] 的纯函数是为了能在 main_test.dart
/// 里验证门控逻辑本身，不需要真的启动 Sentry SDK。
@visibleForTesting
Future<void> bootstrapSentryGatedApp({
  required String dsn,
  required bool analyticsEnabled,
  required Future<void> Function(String dsn, VoidCallback appRunner) initSentry,
  required VoidCallback appRunner,
}) async {
  if (dsn.isNotEmpty && analyticsEnabled) {
    await initSentry(dsn, appRunner);
  } else {
    appRunner();
  }
}

/// 桌面端点击窗口关闭按钮时的行为：只隐藏窗口到系统托盘，
/// **不**断开 VPN、**不**退出进程。
///
/// 托盘（见 tray_controller.dart）存在的意义就是让用户能关掉窗口但保持
/// VPN 连接和后台服务运行——真正退出程序走托盘菜单"退出 ClashMiao"项
/// （TrayController.onTrayMenuItemClick 的 'quit' 分支），只有那里才会
/// disconnect() + destroy()。
///
/// window_manager 的 `setPreventClose(true)` 让 onWindowClose 变成可拦截
/// 事件（native 层已经在关闭时拦下真正的销毁），这里只需要 hide()，
/// 把控制权交还给托盘。
class DesktopShutdownGuard with WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
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
    String url = const String.fromEnvironment('CLASHMIAO_TEST_SUB_URL').trim();
    if (url.isEmpty) {
      url = (env['CLASHMIAO_TEST_SUB_URL'] ?? '').trim();
    }
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
        if (isHttpDownloadUrl(url)) {
          await repo.addByUrl(url, customName: 'dev');
        } else {
          await repo.addByContent(url, name: 'dev');
        }
        debugPrint('[DevBoot] 订阅添加成功');
        container.invalidate(profileListProvider);
        container.invalidate(activeProfileProvider);
        container.invalidate(offlineProxyGroupsProvider);
      } catch (e) {
        debugPrint('[DevBoot] 订阅添加失败: $e');
        return;
      }
    } else {
      debugPrint('[DevBoot] 已有订阅 ${existing.length} 个，跳过添加');
    }

    // 给 UI / status stream 一点时间稳定，然后触发 connect
    await Future<void>.delayed(const Duration(seconds: 2));
    debugPrint('[DevBoot] 自动连接...');
    await container.read(connectionControllerProvider.notifier).toggle();
  } catch (e, st) {
    debugPrint('[DevBoot] 出错: $e\n$st');
  }
}
