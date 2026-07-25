import 'dart:async';
// AppExitResponse 定义在 dart:ui，flutter 的 barrel 文件没有 re-export。
import 'dart:ui' show AppExitResponse;

import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/tray/tray_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 清理最多允许跑这么久，超时就放行退出。
///
/// **不能省。** 返回 [AppExitResponse.exit] 之前操作系统一直在等我们，清理里
/// 任何一处卡住（内核不响应、平台 channel 无回应）都会让 App 永远退不出去——
/// 用户只能强制退出，而强制退出恰好跳过清理，等于把要修的问题变得更糟。
const kDesktopExitCleanupTimeout = Duration(seconds: 5);

/// 桌面端退出守卫：在操作系统真的终止我们之前，先停内核（**还原系统代理**）
/// 并清理托盘。
///
/// ## 为什么必须有
///
/// 桌面端默认开启 `set-system-proxy`，而三个平台的系统代理写的都是**持久化
/// 设置**，只在 sing-box 优雅关闭（listener 的 Close 路径）里才还原：
///
/// - macOS：`networksetup -setwebproxy <服务> 127.0.0.1 <端口>`
/// - Windows：WinINET（`HKCU\...\Internet Settings`）
/// - Linux：`gsettings set org.gnome.system.proxy mode manual`
///
/// 原来只有系统托盘的「退出」和 Ctrl+Q 快捷键走优雅路径。**macOS 上最常用的
/// Cmd+Q 完全不经过 Dart 侧**，按一下就让系统代理永久指向一个已经没人监听的
/// 本地端口——整机浏览器都打不开网页，而 App 界面显示"未连接"。
///
/// ## 为什么用 AppLifecycleListener 而不是自己重写 AppDelegate
///
/// 一开始是在 `macos/Runner/AppDelegate.swift` 里重写
/// `applicationShouldTerminate` + 自建 MethodChannel 做的，实测可用。但查引擎
/// 源码后发现**Flutter 自己就有这条通路**：引擎的 `FlutterAppDelegate` 已经
/// 实现了 `applicationShouldTerminate:`，会发 `System.requestAppExit` platform
/// message，由 `ServicesBinding.handleRequestAppExit()` 交给这里的
/// [AppLifecycleListener.onExitRequested]。
///
/// 自己重写等于**把框架这条通路遮蔽掉**（子类覆盖父类实现）。之前没出问题只是
/// 因为本来没人注册 onExitRequested。改用框架机制有三个实打实的好处：
///
/// 1. **跨平台**：Windows / Linux 的会话结束（注销、关机）走同一条 Dart 回调，
///    不用再各写一份原生代码——那本来是另一个待办项。
/// 2. 少一份原生代码和一条自建 channel 要维护。
/// 3. 不用自己写 `reply(toApplicationShouldTerminate:)` 那套异步回复плumbing。
///
/// 框架**不**提供超时，所以那部分保留自己做（见 [kDesktopExitCleanupTimeout]）。
///
/// ## 拦不住的路径
///
/// 崩溃、强制退出、断电——操作系统不给任何清理机会。那半边由启动时的自愈覆盖
/// （见 `core/proxy/system_proxy_guard.dart`）。
class DesktopExitGuard {
  DesktopExitGuard(this._container);

  final ProviderContainer _container;
  AppLifecycleListener? _listener;

  /// 装上守卫。桌面端 `main()` 里调用一次。
  void install() {
    _listener = AppLifecycleListener(onExitRequested: handleExitRequest);
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }

  /// 操作系统请求退出时的处理。**永远返回 [AppExitResponse.exit]**——我们从不
  /// 取消用户的退出意图，只是借这个机会把该还原的东西还原掉。
  @visibleForTesting
  Future<AppExitResponse> handleExitRequest() async {
    try {
      await performShutdownCleanup(
        disconnect: () =>
            _container.read(connectionControllerProvider.notifier).disconnect(),
        disposeTray: TrayController.instance.dispose,
      ).timeout(kDesktopExitCleanupTimeout);
    } on TimeoutException {
      debugPrint(
        '[Quit] 退出清理超时（${kDesktopExitCleanupTimeout.inSeconds}s），照常退出',
      );
    } catch (e) {
      // performShutdownCleanup 内部已经逐步兜住异常了，这里只是最后一道：
      // 绝不能因为清理出错就把退出卡住。
      debugPrint('[Quit] 退出清理异常，照常退出: $e');
    }
    return AppExitResponse.exit;
  }
}
