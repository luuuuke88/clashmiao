//
//  NetworkStream.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `com.clashmiao.app/network`：默认网络切换事件（Wi-Fi ↔ 蜂窝等）。
//  载荷是空 map，Dart 侧只关心「变了」。
//

import Flutter
import Foundation

public final class NetworkStream: NSObject, FlutterPlugin, FlutterStreamHandler {

    public static var channelName: String {
        "\(Bundle.main.channelNamespace)/network"
    }

    private var channel: FlutterEventChannel?
    private var cancel: (() -> Void)?
    private var pending: DispatchWorkItem?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = NetworkStream()
        instance.channel = FlutterEventChannel(
            name: channelName,
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        instance.channel?.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        cancel = KernelHost.shared.observeNetworkChange { [weak self] in
            // 去抖：切网时系统会连发几次路径更新，合并成一次事件。
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending?.cancel()
                let item = DispatchWorkItem { events([String: Any]()) }
                self.pending = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
            }
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        cancel?()
        cancel = nil
        pending?.cancel()
        pending = nil
        return nil
    }
}
