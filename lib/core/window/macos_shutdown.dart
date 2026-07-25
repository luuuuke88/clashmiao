import 'package:clashmiao/core/providers/app_providers.dart';
import 'package:clashmiao/core/tray/tray_controller.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// macOS 退出清理通道名。原生侧同名常量在
/// `macos/Runner/MainFlutterWindow.swift`。
const macosShutdownChannelName = 'com.clashmiao/shutdown';

/// 原生侧请求清理时用的方法名。
const macosShutdownMethod = 'shutdown';

/// 注册 macOS 的退出清理处理器。
///
/// `AppDelegate.applicationShouldTerminate`（Cmd+Q / 菜单退出 / 系统注销）会
/// 先通过这条通道请求清理、拿到回复后才放行退出，并带 5 秒硬超时兜底。
///
/// ## 不注册会怎样
///
/// Cmd+Q 走 `FlutterAppDelegate` 的默认实现直接终止进程，Dart 侧一行清理都跑
/// 不到。而桌面端默认开启 `set-system-proxy`，sing-box 在 macOS 上是 shell 出去
/// 执行 `networksetup -setwebproxy <服务> 127.0.0.1 <端口>`——**持久化的系统级
/// 设置**，只在优雅关闭（listener 的 Close 路径）里才会被还原。
///
/// 于是：用户按一下 Cmd+Q，系统代理就永久指向一个已经没人监听的本地端口，
/// 浏览器和所有遵循系统代理的程序全部连不上网；重开 App 也不会自动修好，只能
/// 自己去「系统设置 → 网络 → 代理」里手动关掉。
///
/// 拦不住的路径（崩溃、强制退出、断电）不在覆盖范围内——那些情况下操作系统
/// 不给任何清理机会。
///
/// [channel] 只为测试注入；生产走 [macosShutdownChannelName]。
void registerMacosShutdownHandler(
  ProviderContainer container, {
  MethodChannel? channel,
}) {
  final target = channel ?? const MethodChannel(macosShutdownChannelName);
  target.setMethodCallHandler((call) async {
    if (call.method != macosShutdownMethod) return null;
    await performShutdownCleanup(
      disconnect: () =>
          container.read(connectionControllerProvider.notifier).disconnect(),
      disposeTray: TrayController.instance.dispose,
    );
    return null;
  });
}
