import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Dart 侧的退出清理通道，由 `MainFlutterWindow` 建好引擎后注入。
  static var shutdownChannel: FlutterMethodChannel?

  /// Dart 侧最多有这么久做清理，超时就照常退出。
  ///
  /// 这个超时**不能省**：一旦 Dart 侧因为任何原因没回（引擎已销毁、清理里
  /// 自己卡住、异常没被接住），`.terminateLater` 会让 App 永远退不出去——
  /// 用户只能强制退出，而强制退出恰好又跳过清理，等于把要修的问题变得更糟。
  private static let shutdownTimeout: TimeInterval = 5

  private var isTerminating = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 关闭最后一个窗口后继续在后台/托盘运行（VPN 连接和后台服务不受影响）。
    // 真正退出走系统托盘菜单的“退出”项，见 lib/core/tray/tray_controller.dart。
    return false
  }

  /// Cmd+Q / 菜单退出 / `osascript quit` / 系统注销都会走到这里。
  ///
  /// ## 为什么必须拦
  ///
  /// 桌面端默认开启 `set-system-proxy`。sing-box 在 macOS 上是 shell 出去执行
  /// `networksetup -setwebproxy <服务> 127.0.0.1 <端口>`，那是**持久化的系统级
  /// 设置**，不随进程消失；它只在优雅关闭（listener 的 Close 路径）里才会被
  /// `networksetup -setwebproxystate ... off` 还原。
  ///
  /// `FlutterAppDelegate` 的默认实现直接返回 `.terminateNow`，Dart 侧一行清理
  /// 都跑不到。结果是：**用户按一下 Cmd+Q，系统代理就永久指向一个已经没人
  /// 监听的本地端口**——浏览器和所有遵循系统代理的程序全部连不上网，重开 App
  /// 也不会自动修好，只能自己去「系统设置 → 网络 → 代理」里手动关掉。
  ///
  /// 原来只有系统托盘的「退出」和 Ctrl+Q 快捷键走优雅路径，而 Cmd+Q 是 macOS
  /// 上最常用的退出手势。
  ///
  /// 拦不住的路径（崩溃、强制退出、断电）不在本函数覆盖范围内。
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // 超时后我们自己调 reply(true)，系统会再进一次这里；这时必须直接放行，
    // 否则会无限循环等待。
    if isTerminating {
      return .terminateNow
    }
    guard let channel = AppDelegate.shutdownChannel else {
      // 引擎还没建好（启动极早期就退出）——没有需要还原的状态，直接退。
      return .terminateNow
    }
    isTerminating = true

    var replied = false
    let finish = {
      // 只放行一次：Dart 回调和超时都会调到这里，谁先到算谁。
      if replied { return }
      replied = true
      NSApp.reply(toApplicationShouldTerminate: true)
    }

    channel.invokeMethod("shutdown", arguments: nil) { _ in
      // 不看返回值：Dart 侧无论成功、抛错还是 FlutterMethodNotImplemented，
      // 我们都只关心"它已经结束了"，然后放行退出。
      finish()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + AppDelegate.shutdownTimeout) {
      finish()
    }

    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
