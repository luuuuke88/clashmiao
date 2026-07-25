import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 退出清理通道。AppDelegate.applicationShouldTerminate 会在 Cmd+Q 时通过
    // 它请求 Dart 侧停内核（还原系统代理）+ 清托盘，见那边的注释。
    // 通道只在这里建立一次，AppDelegate 拿到的是同一个引擎的 messenger。
    AppDelegate.shutdownChannel = FlutterMethodChannel(
      name: "com.clashmiao/shutdown",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    // 开机启动 MethodChannel
    let channel = FlutterMethodChannel(
      name: "com.clashmiao/auto_start",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { (call, result) in
      if #available(macOS 13.0, *) {
        let service = SMAppService.mainApp
        switch call.method {
        case "getAutoStart":
          result(service.status == .enabled)
        case "setAutoStart":
          guard let args = call.arguments as? [String: Any],
                let enabled = args["enabled"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            return
          }
          do {
            if enabled {
              try service.register()
            } else {
              try service.unregister()
            }
            result(nil)
          } catch {
            result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      } else {
        result(FlutterError(code: "UNSUPPORTED", message: "需要 macOS 13+", details: nil))
      }
    }

    super.awakeFromNib()
  }
}
