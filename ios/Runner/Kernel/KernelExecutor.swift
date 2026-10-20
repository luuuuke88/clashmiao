//
//  KernelExecutor.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  执行层：唯一一条串行后台队列，执行会阻塞的操作（系统授权、拼配置、写盘、
//  提交 / 停止隧道、等扩展重载回执）。命令层永远不直接调用它们。
//
//  取消点都在**提交到系统之前**：被取消的任务不会留下需要回收的隧道。
//  一旦 `startVPNTunnel` 已提交，取消就变成命令层的 Teardown。
//

import Foundation

/// 执行层交给任务的上下文。
final class ExecContext {
    private let lock = NSLock()
    private var flag = false
    let step: (String) -> Void

    init(step: @escaping (String) -> Void) {
        self.step = step
    }

    var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock(); flag = true; lock.unlock()
    }
}

final class KernelExecutor {
    /// 等扩展 `reload` 回执的上限。核心的 20 s 看门狗先于它报告失联；它只负责最终放行被卡住的队列。
    static let reloadReplyTimeout: TimeInterval = 35
    /// `startVPNTunnel` 提交后等隧道状态离开 disconnected 的上限。
    static let tunnelVisibleTimeout: TimeInterval = 5

    private let adapter: TunnelAdapter
    private let store: KernelStore
    private let builder: ConfigBuilding
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "com.clashmiao.kernel.exec", qos: .userInitiated)
    private let lock = NSLock()
    private var contexts: [Int64: ExecContext] = [:]

    init(adapter: TunnelAdapter, store: KernelStore, builder: ConfigBuilding, log: @escaping (String) -> Void) {
        self.adapter = adapter
        self.store = store
        self.builder = builder
        self.log = log
    }

    // MARK: - 提交

    func submitConnect(
        token: Int64, spec: LaunchSpec, launchId: String,
        onStep: @escaping (Int64, String) -> Void, onDone: @escaping (Int64, JobResult) -> Void
    ) {
        run(token, onStep, onDone) { [self] ctx in
            ctx.step(CoordinatorCore.authorizeStep)
            do {
                try adapter.ensureConfigured()
            } catch let e as TunnelAdapterError {
                if case .permissionDenied = e { return .failed(.permissionDenied, e.message) }
                return .failed(.startService, e.message)
            } catch {
                return .failed(.startService, error.localizedDescription)
            }
            if ctx.cancelled { return .cancelled }
            if let failure = prepare(spec, launchId, ctx) { return failure }
            if ctx.cancelled { return .cancelled }
            ctx.step("startTunnel")
            do {
                try adapter.startTunnel()
            } catch {
                return .failed(.startService, (error as? TunnelAdapterError)?.message ?? error.localizedDescription)
            }
            // 等隧道在系统层面可见地离开 disconnected，之后的 off 才一定有东西可以停。
            ctx.step("awaitTunnel")
            let deadline = Date().addingTimeInterval(Self.tunnelVisibleTimeout)
            while adapter.currentStatus.isDown {
                if Date() >= deadline {
                    // 撤销可能迟到的启动：提交了却不可见，不能让它之后悄悄冒出来。
                    adapter.stopTunnel()
                    return .abandoned(.startService, "tunnel did not start")
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            return .launched
        }
    }

    func submitReload(
        token: Int64, spec: LaunchSpec, launchId: String, sessionId: String?,
        onStep: @escaping (Int64, String) -> Void, onDone: @escaping (Int64, JobResult) -> Void
    ) {
        run(token, onStep, onDone) { [self] ctx in
            if let failure = prepare(spec, launchId, ctx) { return failure }
            if ctx.cancelled { return .cancelled }
            ctx.step("reload")
            do {
                let reply = try adapter.sendMessage(
                    ExtensionRequest(op: .reload, launchId: launchId, sessionId: sessionId), timeout: Self.reloadReplyTimeout
                )
                guard reply.ok else {
                    return .failed(reply.failureCode ?? .startService, reply.message ?? "reload failed")
                }
                return .reloaded(sessionId: reply.sessionId ?? "", generation: reply.generation ?? 0)
            } catch {
                return .failed(.startService, (error as? TunnelAdapterError)?.message ?? error.localizedDescription)
            }
        }
    }

    func submitTeardown(
        token: Int64,
        onStep: @escaping (Int64, String) -> Void, onDone: @escaping (Int64, JobResult) -> Void
    ) {
        run(token, onStep, onDone) { [self] ctx in
            ctx.step("stopTunnel")
            adapter.stopTunnel()
            return .tornDown
        }
    }

    /// 与生命周期任务串行执行的一段工作（手选出站的写入用，保证不与重载 / 回收交错）。
    func runSerialized(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    func cancel(token: Int64) {
        lock.lock(); let ctx = contexts[token]; lock.unlock()
        ctx?.cancel()
    }

    // MARK: - 内部

    /// 拼配置 → 落盘意图。返回非空 = 失败结果。
    private func prepare(_ spec: LaunchSpec, _ launchId: String, _ ctx: ExecContext) -> JobResult? {
        ctx.step("buildConfig")
        let built: BuiltConfig
        do {
            built = try builder.build(spec: spec)
        } catch let e as ConfigBuildError {
            switch e {
            case .emptyInput, .assembleFailed: return .failed(.emptyConfiguration, e.message)
            case .writeFailed: return .failed(.startService, e.message)
            }
        } catch {
            return .failed(.emptyConfiguration, error.localizedDescription)
        }
        if ctx.cancelled { return .cancelled }
        ctx.step("commitIntent")
        guard store.commitLaunch(launchId: launchId, spec: spec, built: built) else {
            return .failed(.startService, "cannot persist launch intent")
        }
        builder.prune(keepRevisions: [built.revision])
        return nil
    }

    private func run(
        _ token: Int64,
        _ onStep: @escaping (Int64, String) -> Void,
        _ onDone: @escaping (Int64, JobResult) -> Void,
        _ body: @escaping (ExecContext) -> JobResult
    ) {
        let ctx = ExecContext(step: { name in onStep(token, name) })
        lock.lock(); contexts[token] = ctx; lock.unlock()
        queue.async { [weak self] in
            let result = body(ctx)
            self?.lock.lock(); self?.contexts[token] = nil; self?.lock.unlock()
            onDone(token, result)
        }
    }
}
