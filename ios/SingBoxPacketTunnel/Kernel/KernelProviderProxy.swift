//
//  KernelProviderProxy.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Packet Tunnel 扩展：按落盘的意图（`intent.json` + `final-<rev>.json`）起 / 重载 / 停内核，
//  并把事实写进 `extension-state.json`。扩展对自己的失败**负全责**——Runner 可能被挂起或被杀，
//  所以任何不可恢复的错误都由这里清理资源、写 `failed`、`throw` / `cancelTunnelWithError`
//  （iOS 设计 §2、§6）。
//
//  串行：start 的主体、reload、select、内核自发重载、内存采样都在 `opQueue` 上排队。
//  `stopTunnel` 不经 `opQueue` 排队：它先在锁内置 `stopping`（在途的 start / reload 在检查点看到后放弃），
//  并直接调 `engine.interrupt()` 打断阻塞中的启动（粘性：之后的启动一律立即失败），再把回收投递到 `opQueue`。同步路径 `engine.start()` →
//  `openTun` → `awaitBlocking` → `setTunnelNetworkSettings` 只依赖 NE 自己的回调队列，不依赖 `opQueue`。
//
//  内存（约 50 MB 的观察值）：只读文件 → 启动 → 立即释放配置文本；不解析 JSON、不常驻副本；
//  重载先完整停掉旧服务再启动新的；内核自身按 Packet Tunnel 的内存策略运行（见 KernelBridge.setup）。
//

import Foundation
import Libcore
import NetworkExtension
import os

/// 启动 / 重载失败：带 `FailureCode`，会被写进 state 并以 NSError 抛给系统。
struct KernelStartFailure: Error {
    let code: FailureCode
    let message: String
}

open class KernelProviderProxy: NEPacketTunnelProvider {

    // MARK: - 内核句柄
    //
    // `engine` 由 opQueue 创建与销毁；stopTunnel / 日志转发要在别的线程读它，所以经 flagLock 存取。
    // `serviceRunning` 只在 opQueue 上读写。

    private var engineRef: CoreEngine?
    private var serviceRunning = false
    private var platformBridge: KernelPlatformBridge?

    // MARK: - 串行与停止优先

    private let opQueue = DispatchQueue(label: "com.clashmiao.tunnel.op", qos: .userInitiated)
    private let flagLock = NSLock()
    private var stopping = false
    private var terminated = false // 已经为失败调用过 cancelTunnelWithError

    private var writer: ExtensionStateWriter?
    private var currentLaunchId = ""
    private var lastReload: (launchId: String, reply: ExtensionReply)?
    private var memoryTimer: DispatchSourceTimer?

    private static var processInitialized = false

    // MARK: - Lifecycle entry points

    override open func startTunnel(options: [String: NSObject]?) async throws {
        guard let intent = Self.readIntent() else {
            throw fail(KernelStartFailure(code: .emptyConfiguration, message: "no launch intent"), launchId: "")
        }
        let w = ExtensionStateWriter(url: ProfilePathResolver.extensionStateFile, launchId: intent.launchId)
        writer = w
        currentLaunchId = intent.launchId
        startMemorySampling()

        do {
            // 成功收口（停止复查、发布 running、采样）与 bringUp 在同一个 opQueue 操作里完成：
            // 排队中的重载不会被一个已出队的旧启动把 starting 覆盖成 running。
            try await onOpQueue {
                let effective = try self.bringUp(intent)
                if self.isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }
                self.currentLaunchId = effective.launchId
                w.markRunning(launchId: effective.launchId, revision: effective.finalRevision)
                self.sampleMemory("started")
            }
        } catch let f as KernelStartFailure {
            await onOpQueue { self.teardownLocked() }
            throw fail(f, launchId: intent.launchId)
        } catch {
            await onOpQueue { self.teardownLocked() }
            throw fail(KernelStartFailure(code: .startService, message: error.localizedDescription), launchId: intent.launchId)
        }
    }

    override open func stopTunnel(with reason: NEProviderStopReason) async {
        flagLock.lock()
        stopping = true
        let engine = engineRef
        flagLock.unlock()
        // 打断可能正阻塞在 opQueue 上的启动，并让之后的启动立即失败（之后 opQueue 上的回收再完整关闭）。
        // 用粘性的 interrupt 而不是 stop：stop 若落在「检查完 stopping、start 尚未登记取消信号」之间，
        // 随后的 start 照常启动。engine 还没建出来时，bringUp 在登记 engineRef 的同一把锁下看到 stopping。
        engine?.interrupt()
        // 先记下停止原因（终态粘性：已有 failed 则不覆盖），再回收。
        writer?.markStopped(reason: reason.rawValue)
        memoryTimer?.cancel()
        memoryTimer = nil
        await onOpQueue {
            self.forwardKernelLine("[Tunnel] shutting down, reason=\(reason.rawValue)")
            self.teardownLocked()
        }
    }

    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        guard let request = try? JSONDecoder().decode(ExtensionRequest.self, from: messageData) else {
            return Self.encode(ExtensionReply(ok: false, code: nil, message: "malformed request"))
        }
        let reply: ExtensionReply
        switch request.op {
        case .reload: reply = await handleReload(request)
        case .select: reply = await handleSelect(request)
        }
        return Self.encode(reply)
    }

    override open func sleep() async {
        opQueue.sync { if serviceRunning { engine?.pause() } }
    }

    override open func wake() {
        opQueue.async { if self.serviceRunning { self.engine?.wake() } }
    }

    // MARK: - 应用消息

    private func handleReload(_ request: ExtensionRequest) async -> ExtensionReply {
        guard let w = writer else { return ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "no session") }
        // 目标绑定 (launchId, sessionId)：系统换了实例后，原消息被拒绝。
        if let sid = request.sessionId, !sid.isEmpty, sid != w.sessionId {
            return ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "session changed")
        }
        guard let intent = Self.readIntent(), intent.launchId == request.launchId else {
            return ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "launchId is not the published intent")
        }
        return await onOpQueue {
            // 幂等：同一 launchId 的重复消息直接返回缓存回执，不再重建。
            if let last = self.lastReload, last.launchId == intent.launchId { return last.reply }
            let reply = self.performReload(intent, selfInitiated: false)
            if reply.ok { self.lastReload = (intent.launchId, reply) }
            return reply
        }
    }

    private func handleSelect(_ request: ExtensionRequest) async -> ExtensionReply {
        guard let w = writer, let group = request.group, let outbound = request.outbound else {
            return ExtensionReply(ok: false, code: nil, message: "malformed select")
        }
        return await onOpQueue {
            // 校验与 service 替换在同一条串行队列上：旧 generation 的写入绝不会落到新 service。
            guard self.isRunning, !self.isStopping else {
                return ExtensionReply(ok: false, code: nil, message: "kernel not running")
            }
            let st = w.current
            if let sid = request.sessionId, sid != w.sessionId {
                return ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "session changed")
            }
            if let gen = request.generation, gen != st.generation {
                return ExtensionReply(ok: false, code: ExtensionReply.staleCode,
                                      message: "generation moved \(gen) -> \(st.generation)")
            }
            do {
                guard let engine = self.engine else { throw KernelStartFailure(code: .startService, message: "no engine") }
                try engine.selectOutbound(group, tag: outbound)
                return ExtensionReply(ok: true)
            } catch {
                return ExtensionReply(ok: false, code: nil, message: error.localizedDescription)
            }
        }
    }

    // MARK: - 启动 / 重载（均在 opQueue 上）

    private var isStopping: Bool {
        flagLock.lock(); defer { flagLock.unlock() }
        return stopping
    }

    private var isRunning: Bool { serviceRunning }

    /// 给平台回调用：隧道已进入停止（终态）后，迟到的设置提交一律放弃。
    var isStoppingForBridge: Bool { isStopping }

    private var engine: CoreEngine? {
        flagLock.lock(); defer { flagLock.unlock() }
        return engineRef
    }

    /// 读配置、起命令服务器、建 service、start、绑定。任何一步失败抛 `KernelStartFailure`，
    /// 已创建的资源已经登记在 provider 名下，由调用方统一 `teardownLocked`。
    /// 返回**实际使用**的 intent：final 读不到而重读了更新的 intent 时，上报的 launchId / revision 必须是它的。
    private func bringUp(_ intent: KernelIntent) throws -> KernelIntent {
        if isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }
        let (effective, loaded) = try Self.loadFinalConfig(intent)
        var config = loaded
        sampleMemory("config-read")

        try Self.processSetupOnce()

        let bridge = platformBridge ?? KernelPlatformBridge(self)
        platformBridge = bridge

        let engine: CoreEngine
        if let existing = self.engine {
            engine = existing
        } else {
            // 新建即起命令服务器（App Group 根目录下的 command.sock，Runner 经它订阅）。
            var newError: NSError?
            guard let created = CoreNewEngine(bridge, bridge, &newError), newError == nil else {
                throw KernelStartFailure(code: .startCommandServer,
                                         message: newError?.localizedDescription ?? "CoreNewEngine returned nil")
            }
            // 登记与检查 stopping 在同一把锁下：stopTunnel 要么看到这个 engine 并打断它，要么我们看到 stopping。
            flagLock.lock()
            engineRef = created
            let stoppingNow = stopping
            flagLock.unlock()
            engine = created
            if stoppingNow {
                created.interrupt()
                throw KernelStartFailure(code: .startService, message: "stopped during start")
            }
            forwardKernelLine("[Tunnel] command server ready")
        }
        if isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }

        // 先登记「服务可能在跑」：start 半途失败也要由 teardown 去 stop。
        serviceRunning = true
        sampleMemory("service-created")
        do {
            try engine.start(config)
        } catch {
            config = ""
            let message = error.localizedDescription
            // 内核错误带稳定前缀：create-service:（配置被拒）/ start-service: / canceled:（被停止打断）
            let code: FailureCode = message.hasPrefix("create-service:") ? .createService : .startService
            throw KernelStartFailure(code: code, message: message)
        }
        config = "" // 立即释放配置文本
        sampleMemory("service-started")
        return effective
    }

    /// 就地重载：先完整释放旧 service（保留命令服务器），再按最新 intent 建新的。
    /// 失败 = 不可恢复：回收、写 failed、`cancelTunnelWithError`，不依赖 Runner 在场。
    private func performReload(_ requested: KernelIntent?, selfInitiated: Bool) -> ExtensionReply {
        guard let w = writer, !isStopping else {
            return ExtensionReply(ok: false, code: nil, message: "stopping")
        }
        guard let intent = requested ?? Self.readIntent() else {
            return failReload(KernelStartFailure(code: .emptyConfiguration, message: "no launch intent"), selfInitiated)
        }
        forwardKernelLine("[Tunnel] reloading kernel service")
        w.markReloading(launchId: intent.launchId)
        currentLaunchId = intent.launchId
        reasserting = true
        defer { if !terminatedFlag { reasserting = false } }
        teardownService()
        sampleMemory("reload-released")
        let effective: KernelIntent
        do {
            effective = try bringUp(intent)
        } catch let f as KernelStartFailure {
            return failReload(f, selfInitiated)
        } catch {
            return failReload(KernelStartFailure(code: .startService, message: error.localizedDescription), selfInitiated)
        }
        if isStopping { return failReload(KernelStartFailure(code: .startService, message: "stopped during reload"), selfInitiated) }
        currentLaunchId = effective.launchId
        w.markRunning(launchId: effective.launchId, revision: effective.finalRevision)
        sampleMemory("reload-done")
        if requested != nil, effective.launchId != intent.launchId {
            // 重读到了更新的意图：内核现在跑的是更新的那份（generation 已推进），这条旧操作的回执是 stale，
            // 更新的操作自己的 reload 随后到达。
            return ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "intent moved on during reload")
        }
        return ExtensionReply(ok: true, sessionId: w.sessionId, generation: w.current.generation)
    }

    /// 不可恢复的重载失败：回收、写 `failed`、取消隧道。应用消息路径要**先送出失败回执**再取消，
    /// 否则 IPC 回执可能丢失，Runner 只会看到超时；自发重载没有回执，直接取消。
    private func failReload(_ f: KernelStartFailure, _ selfInitiated: Bool) -> ExtensionReply {
        teardownLocked()
        writer?.markFailed(code: f.code, message: f.message)
        flagLock.lock(); terminated = true; flagLock.unlock()
        let error = NSError(domain: "ClashMiaoTunnel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: f.message, "code": f.code.rawValue,
        ])
        if selfInitiated {
            cancelTunnelWithError(error)
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.cancelTunnelWithError(error)
            }
        }
        return ExtensionReply(ok: false, code: f.code.rawValue, message: f.message)
    }

    private var terminatedFlag: Bool {
        flagLock.lock(); defer { flagLock.unlock() }
        return terminated
    }

    /// 内核回调 `serviceReload()` / 系统代理开关：不阻塞调用方（libbox 回调线程），只入队。
    func requestSelfReload() {
        opQueue.async { [weak self] in
            guard let self, self.isRunning, !self.isStopping else { return }
            _ = self.performReload(nil, selfInitiated: true)
        }
    }

    // MARK: - 回收

    /// 只停服务（重载用，保留命令服务器与桥）。
    private func teardownService() {
        if serviceRunning, let engine {
            do { try engine.stop() } catch {
                forwardKernelLine("[Tunnel] kernel stop failed: \(error.localizedDescription)")
            }
        }
        serviceRunning = false
        platformBridge?.discardCachedSettings()
    }

    /// 完整回收：服务 + 命令服务器（删 socket）。幂等；每一步各自兜底。
    private func teardownLocked() {
        teardownService()
        flagLock.lock()
        let engine = engineRef
        engineRef = nil
        flagLock.unlock()
        if let engine {
            do { try engine.close() } catch {
                NSLog("[ClashMiao.Tunnel] kernel close failed: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - 失败自洽

    /// 写 `failed`，并返回要抛给系统的 NSError（启动路径用 throw，不需要 cancelTunnelWithError）。
    private func fail(_ f: KernelStartFailure, launchId: String) -> NSError {
        if writer == nil {
            writer = ExtensionStateWriter(url: ProfilePathResolver.extensionStateFile, launchId: launchId)
        }
        writer?.markFailed(code: f.code, message: f.message)
        NSLog("[ClashMiao.Tunnel] start failed: %@ (%@)", f.code.rawValue, f.message)
        return NSError(domain: "ClashMiaoTunnel", code: 1, userInfo: [
            NSLocalizedDescriptionKey: f.message, "code": f.code.rawValue,
        ])
    }

    // MARK: - 配置与进程级初始化

    private static func readIntent() -> KernelIntent? {
        guard let i = KernelFile.read(KernelIntent.self, from: ProfilePathResolver.intentFile),
              i.version == KernelIntent.currentVersion else { return nil }
        return i
    }

    /// 读 intent 引用的最终配置。读不到（Runner 恰好发布了新的并清理了旧的）则重读一次 intent 再试，仍失败 = `emptyConfiguration`。
    private static func loadFinalConfig(_ intent: KernelIntent) throws -> (KernelIntent, String) {
        var candidate = intent
        for attempt in 0..<2 {
            if let path = candidate.finalConfigPath, let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty {
                return (candidate, text)
            }
            if attempt == 0, let again = readIntent() { candidate = again }
        }
        throw KernelStartFailure(code: .emptyConfiguration, message: "final config unavailable")
    }

    /// 内核的进程级 Setup 每个进程只做一次。BasePath 与 Runner 相同（App Group 根，命令 socket 在这里），
    /// 工作目录是扩展自己的；`memoryLimited` 让内核按 Packet Tunnel 的内存策略运行。
    private static func processSetupOnce() throws {
        if processInitialized { return }
        do {
            try KernelBridge.setup(
                basePath: ProfilePathResolver.sharedContainer.path,
                workingPath: ProfilePathResolver.runtimeWorkingDirectory.path,
                tempPath: ProfilePathResolver.cacheDirectory.path,
                memoryLimited: true
            )
        } catch {
            throw KernelStartFailure(code: .startCommandServer, message: "kernel setup failed: \(error)")
        }
        processInitialized = true
    }

    private static func encode(_ reply: ExtensionReply) -> Data? {
        try? JSONEncoder().encode(reply)
    }

    // MARK: - 日志

    /// 写一行到内核的日志流（Runner 消费），内核不在时落到 NSLog。
    func forwardKernelLine(_ message: String) {
        if let engine {
            engine.writeLog(message)
        } else {
            NSLog("%@", message)
        }
    }

    // MARK: - 内存采样（诊断；Apple 不保证固定上限）

    private func startMemorySampling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.sampleMemory(nil) }
        timer.resume()
        memoryTimer = timer
    }

    private func sampleMemory(_ stage: String?) {
        let available = Int64(os_proc_available_memory())
        writer?.noteFootprint(Self.physFootprint())
        if writer?.noteAvailableMemory(available) == true || stage != nil {
            if let stage {
                NSLog("[ClashMiao.Tunnel] memory %@: available=%lld KB footprint=%lld KB",
                      stage, available / 1024, Self.physFootprint() / 1024)
            }
        }
    }

    /// 进程的 `phys_footprint`（jetsam 判定用的口径）；取不到返回 0。
    private static func physFootprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    // MARK: - opQueue 桥

    private func onOpQueue<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            opQueue.async {
                do { cont.resume(returning: try body()) } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func onOpQueue<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { cont in
            opQueue.async { cont.resume(returning: body()) }
        }
    }
}
