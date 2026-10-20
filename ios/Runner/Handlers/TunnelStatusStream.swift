//
//  TunnelStatusStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `com.clashmiao.app/service.status`：从权威快照派生的兼容流（Starting / Started / Stopping / Stopped），
//  只供统计 / 分组订阅门控；连接状态的唯一真值是 `/kernel.snapshot`。
//

import Flutter
import Foundation

public final class TunnelStatusStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/service.status"
    }

    private var channel: FlutterEventChannel?
    private var unsubscribe: (() -> Void)?
    private var generation = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TunnelStatusStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        generation += 1
        let gen = generation
        let coordinator = KernelHost.shared.coordinator
        coordinator.whenReady(timeout: 30) { [weak self] ready in
            guard ready else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                var last: String?
                self.unsubscribe = coordinator.observeSnapshot { snapshot in
                    let label = Self.label(snapshot.status)
                    if label == last { return }
                    last = label
                    DispatchQueue.main.async { if self.generation == gen { events(["status": label]) } }
                }
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        generation += 1
        unsubscribe?()
        unsubscribe = nil
        return nil
    }

    static func label(_ status: KernelStatus) -> String {
        switch status {
        case .starting: return "Starting"
        case .started: return "Started"
        case .stopping: return "Stopping"
        case .stopped: return "Stopped"
        }
    }
}
