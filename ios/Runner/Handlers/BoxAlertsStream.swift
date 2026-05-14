//
//  BoxAlertsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Bridges TunnelManager's `alert` publisher to the Dart
//  `watchAlerts` stream. The Dart side expects a JSON-encodable map
//  with `status`, `alert` and (optional) `message` keys.
//

import Foundation
import Combine
import Flutter

public final class BoxAlertsStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/service.alerts"
    }

    private var channel: FlutterEventChannel?
    private var subscription: AnyCancellable?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BoxAlertsStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        subscription = TunnelManager.shared.$alert.sink { alert in
            // Build the payload defensively: keys with nil values get
            // dropped because Flutter's JSON codec rejects nil entries.
            var payload: [String: Any] = ["status": "Stopped"]
            if let category = alert.category {
                payload["alert"] = category.rawValue
            }
            if let detail = alert.detail {
                payload["message"] = detail
            }
            events(payload)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        subscription?.cancel()
        subscription = nil
        return nil
    }
}
