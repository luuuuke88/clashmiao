//
//  LogLinesStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Streams the kernel's log buffer to Dart. The Dart side expects
//  `List<String>` (a list of recent lines), which is exactly what
//  `KernelCommandClient.bufferedLogs` accumulates.
//

import Foundation
import Combine
import Flutter
import Libcore

public final class LogLinesStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/service.logs"
    }

    private var channel: FlutterEventChannel?
    private var sink: FlutterEventSink?
    private var commandClient: KernelCommandClient?
    private var subscription: AnyCancellable?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = LogLinesStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FileManager.default.changeCurrentDirectoryPath(
            ProfilePathResolver.sharedContainer.path
        )
        sink = events
        let client = KernelCommandClient(.kernelLog)
        commandClient = client
        subscription = client.$bufferedLogs.sink { [weak self] lines in
            // Hop to the platform thread to keep Flutter happy.
            DispatchQueue.main.async {
                self?.sink?(lines)
            }
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
}
