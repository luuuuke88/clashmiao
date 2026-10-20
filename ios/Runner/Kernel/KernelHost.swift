//
//  KernelHost.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  进程级装配：把真实的 NE 适配器、App Group 路径、内核拼装接成唯一的 `KernelCoordinator`。
//  Flutter 桥（Pigeon 与各条事件通道）都从这里拿协调器。
//

import Foundation
import Libcore
import Network
import UIKit

final class KernelHost {

    static let shared = KernelHost()

    let controller = TunnelController()
    let coordinator: KernelCoordinator
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.clashmiao.kernel.network")
    private var networkListeners: [Int: () -> Void] = [:]
    private var nextListenerId = 0
    private let listenerLock = NSLock()
    private var lastSignature: String?

    private init() {
        let store = KernelStore(
            intentURL: ProfilePathResolver.intentFile,
            stateURL: ProfilePathResolver.extensionStateFile
        )
        let builder = ConfigBuilder(
            assemble: { path, options in try KernelBridge.buildFullConfig(profilePath: path, options: options) },
            directory: ProfilePathResolver.kernelDirectory,
            log: { NSLog("[ClashMiao] %@", $0) }
        )
        coordinator = KernelCoordinator(adapter: controller, store: store, builder: builder)
        // 偏好加载完成、事实读入核心之后才允许发布快照。
        controller.loadExisting { [coordinator] in coordinator.markReady() }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [coordinator] _ in coordinator.resync() }

        startNetworkMonitor()
    }

    // MARK: - 网络变化

    /// 订阅「默认网络变了」（去抖后）。返回取消函数。
    func observeNetworkChange(_ listener: @escaping () -> Void) -> () -> Void {
        listenerLock.lock()
        nextListenerId += 1
        let id = nextListenerId
        networkListeners[id] = listener
        listenerLock.unlock()
        return { [weak self] in
            self?.listenerLock.lock()
            self?.networkListeners[id] = nil
            self?.listenerLock.unlock()
        }
    }

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            // 签名：是否可用 + 可用接口类型集合。只在它变化时才算「网络换了」，
            // 同一张网络上的指标抖动（expensive / constrained 翻转）不触发。
            let types: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .loopback, .other]
            let used = types.filter { path.usesInterfaceType($0) }.map { "\($0)" }.sorted().joined(separator: ",")
            let signature = "\(path.status == .satisfied)|\(used)"
            if signature == self.lastSignature { return }
            let first = self.lastSignature == nil
            self.lastSignature = signature
            self.coordinator.networkResolved(Int64(truncatingIfNeeded: signature.hashValue))
            if first { return } // 首次回调只是当前网络，不是变化
            self.listenerLock.lock()
            let ls = Array(self.networkListeners.values)
            self.listenerLock.unlock()
            ls.forEach { $0() }
        }
        monitor.start(queue: monitorQueue)
    }
}
