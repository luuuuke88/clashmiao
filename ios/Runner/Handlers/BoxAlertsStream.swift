//
//  BoxAlertsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `com.clashmiao.app/service.alerts`：只剩与连接生命周期无关的提示。目前 iOS 没有这类提示，
//  通道保留（Dart 侧会订阅它），不发任何事件。启动失败 / 授权被拒 / 超时一律在内核快照的
//  `lastFailure` 里，不走这里。
//

import Foundation
import Flutter

public final class BoxAlertsStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/service.alerts"
    }

    private var channel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BoxAlertsStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? { nil }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}
