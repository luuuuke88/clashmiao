//
//  ProxyGroupsStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Streams the live outbound-group state from the kernel to Dart.
//  Backed by `KernelCommandClient` in `.proxyGroups` mode. The Dart
//  side decodes the payload via JSON, so we encode the snapshot here
//  and ship it as a string (Flutter's standard codec doesn't handle
//  arbitrary Codable types directly).
//

import Foundation
import Combine
import Flutter
import Libcore

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
        // libcore reads cwd-relative paths, so make sure we're inside
        // the shared container before we open the command socket.
        FileManager.default.changeCurrentDirectoryPath(
            ProfilePathResolver.sharedContainer.path
        )
        sink = events
        let client = KernelCommandClient(.proxyGroups)
        commandClient = client
        subscription = client.$outboundGroups.sink { [weak self] groups in
            self?.forward(groups)
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

    private func forward(_ groups: [OutboundGroupSnapshot]?) {
        guard let groups else { return }
        guard
            let data = try? JSONEncoder().encode(groups),
            let json = String(data: data, encoding: .utf8)
        else { return }
        DispatchQueue.main.async { [weak self] in
            self?.sink?(json)
        }
    }
}
