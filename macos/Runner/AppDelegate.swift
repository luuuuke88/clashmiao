import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭最后一个窗口后继续在后台/托盘运行（VPN 连接和后台服务不受影响）。
    // 真正退出走系统托盘菜单的“退出”项，见 lib/core/tray/tray_controller.dart。
    return false
  }

  // 特意**不**重写 applicationShouldTerminate：引擎的 FlutterAppDelegate 已经
  // 实现了它，会发 `System.requestAppExit` 交给 Dart 侧的
  // AppLifecycleListener.onExitRequested 处理（见 lib/core/window/
  // desktop_exit_guard.dart）。在这里重写等于把框架那条通路遮蔽掉，还得自己
  // 写一遍异步回复和超时，而且只覆盖 macOS 一个平台。

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
