import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭最后一个窗口后继续在后台/托盘运行（VPN 连接和后台服务不受影响）。
    // 真正退出走系统托盘菜单的“退出”项，见 lib/core/tray/tray_controller.dart。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
