//
//  ChannelMethodHandler.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `com.clashmiao.app/method` MethodChannel 的 iOS 侧。与 Android 一致，只保留 Dart 仍在用的
//  `generate_warp_config`；连接生命周期与内核配置都走 Pigeon（见 `PigeonBridge`）。
//

import Flutter
import Libcore

public final class ChannelMethodHandler: NSObject, FlutterPlugin {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/method"
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(ChannelMethodHandler(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "generate_warp_config" else {
            result(FlutterMethodNotImplemented)
            return
        }
        guard
            let args = call.arguments as? [String: Any],
            let licenseKey = args["license-key"] as? String,
            let accountId = args["previous-account-id"] as? String,
            let accessToken = args["previous-access-token"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
            return
        }
        // 注册请求会联网，放到后台，结果回主线程。
        DispatchQueue.global(qos: .userInitiated).async {
            let reply: Any
            do {
                reply = try KernelBridge.generateWarpCredential(
                    licenseKey: licenseKey,
                    previousAccountId: accountId,
                    previousAccessToken: accessToken
                )
            } catch {
                // 与 Android 抛异常的表现一致：Dart 侧拿到平台异常，而不是把错误文本当成配置。
                let message = (error as? KernelBridgeError)?.message ?? error.localizedDescription
                reply = FlutterError(code: "generate_warp_config", message: message, details: nil)
            }
            DispatchQueue.main.async { result(reply) }
        }
    }
}
