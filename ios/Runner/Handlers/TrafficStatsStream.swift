//
//  TrafficStatsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Pushes per-tick libcore status messages (uplink/downlink, total
//  bytes, connection counters) to Dart via the `/stats` event
//  channel. The Dart side decodes the map into `BoxStats`.
//

import Foundation
import Combine
import Flutter
import Libcore

public final class TrafficStatsStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/stats"
    }

    private var channel: FlutterEventChannel?
    private var sink: FlutterEventSink?
    private var commandClient: KernelCommandClient?
    private var subscription: AnyCancellable?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TrafficStatsStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FileManager.default.changeCurrentDirectoryPath(
            ProfilePathResolver.sharedContainer.path
        )
        sink = events
        let client = KernelCommandClient(.runtimeStatus)
        commandClient = client
        subscription = client.$latestStatus.sink { [weak self] status in
            self?.forward(status)
        }
        client.connect()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        commandClient?.disconnect()
        commandClient = nil
        subscription?.cancel()
        subscription = nil
        sink = nil
        return nil
    }

    private func forward(_ status: LibboxStatusMessage?) {
        guard let status, let sink else { return }
        // Field names mirror the Dart `BoxStats.fromJson` decoder.
        let payload: [String: Any] = [
            "connections-in":  status.connectionsIn,
            "connections-out": status.connectionsOut,
            "uplink":          status.uplink,
            "downlink":        status.downlink,
            "uplink-total":    status.uplinkTotal,
            "downlink-total":  status.downlinkTotal,
        ]
        sink(payload)
    }
}
