//
//  KernelCommandClient.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  订阅扩展里内核的命令流（统计 / 分组 / 日志）。内核跑在 Packet Tunnel 扩展里，命令服务器监听
//  App Group 根目录下的 unix socket；Runner 经 `CoreClient` 连它（两个进程 Setup 同一个 BasePath）。
//
//  重连：订阅失败（扩展还没起来）或断线（扩展重载、被系统回收、用户断开）后按 0.5 / 1 / 2 / 4 s
//  （封顶 4 s）退避重试，直到 `disconnect()`。所以扩展晚启动、重启之后，流会自己接上。
//

import Foundation
import Libcore

/// 一个话题一个实例；结果经 `@Published` 交给 Combine 订阅方（Flutter 的 EventChannel 处理器）。
public class KernelCommandClient: ObservableObject {

    public enum Topic {
        case runtimeStatus  // 统计：线格式 JSON 解码成的字典
        case proxyGroups    // 分组：线格式 JSON 原文
        case kernelLog      // 日志：最近若干行
    }

    // MARK: - 状态（只在 `queue` 上读写）

    private let topic: Topic
    private let maxBufferedLogLines: Int
    private let queue = DispatchQueue(label: "com.clashmiao.kernel.command-client")
    private var client: CoreClient?
    private var subscription: CoreSubscription?
    private var active = false
    /// 每次 connect / disconnect / 断线都换代：迟到的回调与重试只认自己那一代。
    private var generation = 0
    private var attempt = 0

    private static let backoff: [TimeInterval] = [0.5, 1, 2, 4]

    // MARK: - 发布给订阅方（主线程）

    @Published public private(set) var isConnected = false
    /// 统计帧：`connections-in` / `connections-out` / `uplink` / `downlink` / `uplink-total` / `downlink-total`。
    @Published public private(set) var latestStats: [String: Any]?
    /// 分组帧原文（线格式：`[{tag,type,selected,items:[{tag,type,url-test-delay}]}]`）。
    @Published public private(set) var groupsJSON: String?
    @Published public private(set) var bufferedLogs: [String] = []

    public init(_ topic: Topic, maxBufferedLogLines: Int = 300) {
        self.topic = topic
        self.maxBufferedLogLines = maxBufferedLogLines
    }

    deinit {
        let sub = subscription
        let c = client
        queue.async {
            try? sub?.close()
            try? c?.close()
        }
    }

    // MARK: - 生命周期

    /// 开始订阅（幂等）。连不上会按退避一直重试，直到 `disconnect()`。
    public func connect() {
        queue.async {
            guard !self.active else { return }
            self.active = true
            self.generation += 1
            self.attempt = 0
            self.subscribe(self.generation)
        }
    }

    /// 停止订阅与重试（幂等）。
    public func disconnect() {
        queue.async {
            self.active = false
            self.generation += 1
            let sub = self.subscription
            self.subscription = nil
            try? sub?.close()
            DispatchQueue.main.async { self.isConnected = false }
        }
    }

    // MARK: - 订阅与重连（queue 上）

    private func subscribe(_ gen: Int) {
        guard active, gen == generation else { return }
        do {
            try KernelBridge.setupRunnerOnce()
            if client == nil { client = CoreNewClient() }
            guard let client else {
                throw KernelBridgeError.invalidArguments("cannot create command client")
            }
            let handler = Handler(owner: self, generation: gen)
            if topic == .kernelLog {
                // 日志流连上后先回放内核的环形缓冲：清掉旧缓冲，避免重复。
                DispatchQueue.main.async { self.bufferedLogs = [] }
            }
            let sub: CoreSubscription?
            switch topic {
            case .runtimeStatus: sub = try client.subscribeStats(handler, intervalMillis: 1000)
            case .proxyGroups: sub = try client.subscribeGroups(handler)
            case .kernelLog: sub = try client.subscribeLogs(handler)
            }
            guard gen == generation, active else {
                try? sub?.close()
                return
            }
            subscription = sub
            attempt = 0
            DispatchQueue.main.async { self.isConnected = true }
        } catch {
            scheduleRetry(gen)
        }
    }

    private func scheduleRetry(_ gen: Int) {
        guard active, gen == generation else { return }
        let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
        attempt += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.subscribe(gen)
        }
    }

    /// 内核报告断线（服务停止、扩展退出）：换一代、退避重连。
    fileprivate func handleDisconnected(_ gen: Int) {
        queue.async {
            guard self.active, gen == self.generation else { return }
            self.generation += 1
            let next = self.generation
            let sub = self.subscription
            self.subscription = nil
            DispatchQueue.main.async { self.isConnected = false }
            // 关闭放到别的线程：断线回调可能还在流 goroutine 的调用栈里，Close 要等它退出。
            DispatchQueue.global(qos: .utility).async { try? sub?.close() }
            self.scheduleRetry(next)
        }
    }

    // MARK: - 回调（Go 线程 → queue 核对代次 → 主线程）

    /// 只投递当前这一代的帧：断线换代之后，旧订阅迟到的帧不再发布。
    private func deliver(_ gen: Int, _ publish: @escaping () -> Void) {
        queue.async {
            guard self.active, gen == self.generation else { return }
            DispatchQueue.main.async(execute: publish)
        }
    }

    fileprivate func deliverStats(_ json: String, _ gen: Int) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        deliver(gen) { self.latestStats = dict }
    }

    fileprivate func deliverGroups(_ json: String, _ gen: Int) {
        deliver(gen) { self.groupsJSON = json }
    }

    fileprivate func deliverLog(_ line: String, _ gen: Int) {
        deliver(gen) {
            if self.bufferedLogs.count >= self.maxBufferedLogLines {
                self.bufferedLogs.removeFirst(self.bufferedLogs.count - self.maxBufferedLogLines + 1)
            }
            self.bufferedLogs.append(line)
        }
    }

    /// 同时实现三类处理器协议；按话题只会收到其中一类回调。
    private final class Handler: NSObject, CoreStatsHandlerProtocol, CoreGroupsHandlerProtocol, CoreLogHandlerProtocol {
        private weak var owner: KernelCommandClient?
        private let generation: Int

        init(owner: KernelCommandClient, generation: Int) {
            self.owner = owner
            self.generation = generation
        }

        func onStats(_ json: String?) {
            guard let json else { return }
            owner?.deliverStats(json, generation)
        }

        func onGroups(_ json: String?) {
            guard let json else { return }
            owner?.deliverGroups(json, generation)
        }

        func onLog(_ line: String?) {
            guard let line else { return }
            owner?.deliverLog(line, generation)
        }

        func onDisconnected(_ message: String?) {
            owner?.handleDisconnected(generation)
        }
    }
}
