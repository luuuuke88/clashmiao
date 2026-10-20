//
//  KernelSnapshotStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `com.clashmiao.app/kernel.snapshot`：权威内核快照（JSON map，订阅时先推当前值）。
//  `ready` 之前不推任何东西（绝不先发默认 stopped 让 Dart 当权威值），超时由 Dart 的退避重订阅接管。
//

import Flutter
import Foundation

public final class KernelSnapshotStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/kernel.snapshot"
    }

    private var channel: FlutterEventChannel?
    private var unsubscribe: (() -> Void)?
    private var generation = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = KernelSnapshotStream()
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
            // 订阅已被取消 / 换代：丢弃。
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.unsubscribe = coordinator.observeSnapshot { snapshot in
                    let payload = snapshot.toWireMap()
                    DispatchQueue.main.async { if self.generation == gen { events(payload) } }
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
}
