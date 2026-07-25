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
