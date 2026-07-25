import 'dart:async';
import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/router/app_router.dart';
import 'package:clashmiao/core/settings/network_settings.dart';
import 'package:clashmiao/core/update/update_checker.dart';
import 'package:clashmiao/shared/components/update_available_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App 启动后静默检查一次更新：发现新版本才弹「发现新版本」对话框（见
/// `update_available_dialog.dart`），没有新版本 / `GITHUB_REPO_SLUG` 为空 /
/// 网络失败时什么都不做——不产生任何视觉噪音，也绝不让启动流程崩溃。
///
/// 跟关于页手动点「检查更新」是完全独立的两条触发路径，共用同一个
/// [UpdateChecker.checkOnce]，互不依赖、互不影响。
///
/// 拿 BuildContext 走 [appRouterNavigatorKey]（GoRouter 挂在 MaterialApp.router
/// 上的根 Navigator key）而不是尝试在 `main()` 里自己攒一个——`main()`
/// 调用这个函数的时候整个 Widget 树还没建好，压根没有 context 可用；
/// [initialDelay] 默认给首帧渲染留出缓冲时间，确保调用时 `currentContext`
/// 已经指向一棵挂载好的树。
///
/// 不照抄参照项目对应逻辑的原因：确认过参照项目那处实现因为路由结构问题，
/// 实际触发路径几乎不会被用户看到（哑逻辑）；这里通过根 Navigator key
/// 拿到的 context 只要 App 完成首帧渲染就一定可用，是真正有效可见的版本。
Future<void> runStartupUpdateCheck(
  ProviderContainer container, {
  Duration initialDelay = const Duration(seconds: 3),

  /// 单测注入点：默认用 [appRouterNavigatorKey] 拿 context。
  BuildContext? Function()? contextProvider,

  /// 单测注入点：默认走真实的 [UpdateChecker.checkOnce]。
  Future<String?> Function(SharedPreferences prefs, {Dio? dio, int mixedPort})?
  checkOnce,
}) async {
  try {
    if (initialDelay > Duration.zero) {
      await Future<void>.delayed(initialDelay);
    }

    final prefs = await container.read(sharedPreferencesProvider.future);
    final mixedPort = container.read(networkSettingsProvider).mixedPort;
    final doCheck = checkOnce ?? UpdateChecker.checkOnce;
    final latestTag = await doCheck(prefs, mixedPort: mixedPort);
    if (latestTag == null) return;

    final getContext =
        contextProvider ?? (() => appRouterNavigatorKey.currentContext);
    final context = getContext();
    if (context == null || !context.mounted) return;

    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    // 故意不 await 这个弹窗——它的 Future 要等用户点"稍后"/"立即更新"才会
    // resolve，而这是一次性的"发现即弹"通知，不是需要等用户操作完才算
    // "启动检查完成"的流程；调用弹窗过程中任何同步异常（比如 context 失效）
    // 仍然会被外层 try/catch 兜住。
    unawaited(
      showUpdateAvailableDialog(
        context,
        currentVersion: info.version,
        latestVersion: latestTag.replaceFirst('v', ''),
      ),
    );
  } catch (e, st) {
    // 静默失败：启动自动检查绝不能因为网络/平台异常影响正常启动流程。
    debugPrint('[StartupUpdateCheck] 启动自动检查更新失败: $e\n$st');
  }
}
