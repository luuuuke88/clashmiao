//
//  TrafficStatsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Pushes per-tick kernel stats frames (uplink/downlink rates, total
//  bytes, connection counters) to Dart via the `/stats` event
//  channel. The Dart side decodes the map into `BoxStats`.
//

import Foundation
import Combine
import Flutter

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
        sink = events
        let client = KernelCommandClient(.runtimeStatus)
        commandClient = client
        subscription = client.$latestStats.sink { [weak self] stats in
            self?.forward(stats)
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

    private func forward(_ stats: [String: Any]?) {
        // 已经是线格式的键名（与 Dart `BoxStats.fromJson` 一致），原样转发。
        guard let stats, let sink else { return }
        sink(stats)
    }
}
