//
//  TunnelStatusStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Mirrors NEVPNStatus changes from `TunnelManager.state` to the
//  Dart-side `watchStatus()` stream. Status strings use Pascal-case
//  ("Started", "Stopping", …) – `PlatformBoxService._parseStatus`
//  lower-cases them before matching, so anything is fine as long as
//  the spelling matches Android's enum.
//

import Foundation
import Combine
import Flutter
import NetworkExtension

public final class TunnelStatusStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/service.status"
    }

    private var channel: FlutterEventChannel?
    private var subscription: AnyCancellable?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TunnelStatusStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        subscription = TunnelManager.shared.$state.sink { status in
            let label: String
            switch status {
            case .reasserting, .connecting:
                label = "Starting"
            case .connected:
                label = "Started"
            case .disconnecting:
                label = "Stopping"
            case .disconnected, .invalid:
                label = "Stopped"
            @unknown default:
                label = "Stopped"
            }
            events(["status": label])
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        subscription?.cancel()
        subscription = nil
        return nil
    }
}
