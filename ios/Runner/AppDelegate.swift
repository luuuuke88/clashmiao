import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        registerPlatformChannels()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    }

    // MARK: - Platform Channels

    private func registerPlatformChannels() {
        guard let controller = window?.rootViewController as? FlutterViewController else {
            return
        }
        let messenger = controller.binaryMessenger

        // Method Channel
        let methodChannel = FlutterMethodChannel(
            name: "com.clashmiao.app/method",
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }

        // Status Event Channel
        let statusChannel = FlutterEventChannel(
            name: "com.clashmiao.app/service.status",
            binaryMessenger: messenger,
            codec: FlutterJSONMethodCodec.sharedInstance()
        )
        statusChannel.setStreamHandler(StatusStreamHandler())

        // Stats Event Channel
        let statsChannel = FlutterEventChannel(
            name: "com.clashmiao.app/stats",
            binaryMessenger: messenger,
            codec: FlutterJSONMethodCodec.sharedInstance()
        )
        statsChannel.setStreamHandler(StatsStreamHandler())

        // Groups Event Channel
        let groupsChannel = FlutterEventChannel(
            name: "com.clashmiao.app/groups",
            binaryMessenger: messenger
        )
        groupsChannel.setStreamHandler(GroupsStreamHandler())

        // Logs Event Channel
        let logsChannel = FlutterEventChannel(
            name: "com.clashmiao.app/service.logs",
            binaryMessenger: messenger
        )
        logsChannel.setStreamHandler(LogsStreamHandler())
    }

    // MARK: - Method Call Handler

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            // TODO: 初始化 VPN Manager 和 sing-box 核心
            result(true)

        case "start":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 通过 NetworkExtension 启动 VPN，传入配置路径
            result(true)

        case "stop":
            // TODO: 停止 VPN 连接
            result(true)

        case "restart":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 重启 VPN 连接
            result(true)

        case "parse_config":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String,
                  let tempPath = args["tempPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 调用 sing-box 核心验证配置
            result("")

        case "select_outbound":
            guard let args = call.arguments as? [String: Any],
                  let groupTag = args["groupTag"] as? String,
                  let outboundTag = args["outboundTag"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 调用 sing-box 切换出站节点
            result(true)

        case "url_test":
            guard let args = call.arguments as? [String: Any],
                  let groupTag = args["groupTag"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 调用 sing-box 执行延迟测试
            result(true)

        case "generate_config":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少参数", details: nil))
                return
            }
            // TODO: 生成完整 sing-box 配置
            result("")

        case "change_config_options":
            // TODO: 更新配置选项
            result(true)

        case "clear_logs":
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Stream Handlers

class StatusStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // 初始状态
        events(["status": "stopped"])
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

class StatsStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // TODO: 启动流量统计上报
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}

class GroupsStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // TODO: 启动代理分组监听
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}

class LogsStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        // TODO: 启动日志监听
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}
