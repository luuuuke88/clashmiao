//
//  ProxyGroupsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Streams the live outbound-group state from the kernel to Dart.
//  Backed by `KernelCommandClient` in `.proxyGroups` mode. The kernel
//  already emits the wire-format JSON string the Dart side decodes,
//  so frames are forwarded verbatim.
//

import Foundation
import Combine
import Flutter

public final class ProxyGroupsStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/groups"
    }

    private var channel: FlutterEventChannel?
    private var sink: FlutterEventSink?
    private var commandClient: KernelCommandClient?
    private var subscription: AnyCancellable?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ProxyGroupsStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        let client = KernelCommandClient(.proxyGroups)
        commandClient = client
        subscription = client.$groupsJSON.sink { [weak self] json in
            self?.forward(json)
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

    private func forward(_ json: String?) {
        // 内核推来的已经是线格式 JSON（与 Android 同一份），原样交给 Dart。
        guard let json, let sink else { return }
        sink(json)
    }
}
