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
//  再把回收投递到 `opQueue`。同步路径 `service.start()` → `openTun` → `awaitBlocking` →
//  `setTunnelNetworkSettings` 只依赖 NE 自己的回调队列，不依赖 `opQueue`。
//
//  内存（约 50 MB 的观察值）：只读文件 → 建 service → 立即释放配置文本；不解析 JSON、不常驻副本；
//  重载先完整释放旧 service 再建新的。
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

    // MARK: - libcore handles（只在 opQueue 上读写，teardown 除外）

    private var commandServer: LibboxCommandServer?
    private var boxService: LibboxBoxService?
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
        flagLock.unlock()
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
        opQueue.sync { boxService?.pause() }
    }

    override open func wake() {
        opQueue.async { self.boxService?.wake() }
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
                try KernelBridge.withStandaloneClient { try $0.selectOutbound(group, outboundTag: outbound) }
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

    private var isRunning: Bool { boxService != nil }

    /// 读配置、起命令服务器、建 service、start、绑定。任何一步失败抛 `KernelStartFailure`，
    /// 已创建的资源已经登记在 provider 名下，由调用方统一 `teardownLocked`。
    /// 返回**实际使用**的 intent：final 读不到而重读了更新的 intent 时，上报的 launchId / revision 必须是它的。
    private func bringUp(_ intent: KernelIntent) throws -> KernelIntent {
        if isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }
        let (effective, loaded) = try Self.loadFinalConfig(intent)
        var config = loaded
        sampleMemory("config-read")

        try Self.processSetupOnce()
        LibboxSetMemoryLimit(true)

        let bridge = platformBridge ?? KernelPlatformBridge(self)
        platformBridge = bridge

        if commandServer == nil {
            let server = LibboxNewCommandServer(bridge, Int32(30))
            do {
                try server?.start()
            } catch {
                try? server?.close()
                throw KernelStartFailure(code: .startCommandServer, message: error.localizedDescription)
            }
            commandServer = server
            forwardKernelLine("[Tunnel] command server ready")
        }
        if isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }

        var newError: NSError?
        let service = LibboxNewService(config, bridge, &newError)
        config = "" // 立即释放配置文本
        if let newError {
            throw KernelStartFailure(code: .createService, message: newError.localizedDescription)
        }
        guard let service else {
            throw KernelStartFailure(code: .createService, message: "LibboxNewService returned nil")
        }
        // 所有权立刻归 provider：之后无论 start 成败，teardown 都能关掉它。
        boxService = service
        sampleMemory("service-created")
        if isStopping { throw KernelStartFailure(code: .startService, message: "stopped during start") }
        do {
            try service.start()
        } catch {
            throw KernelStartFailure(code: .startService, message: error.localizedDescription)
        }
        commandServer?.setService(service)
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

    /// 只释放 service（重载用，保留命令服务器与桥）。
    private func teardownService() {
        commandServer?.setService(nil)
        if let service = boxService {
            do { try service.close() } catch {
                forwardKernelLine("[Tunnel] kernel close failed: \(error.localizedDescription)")
            }
            boxService = nil
        }
        platformBridge?.discardCachedSettings()
    }

    /// 完整回收：service + 命令服务器。幂等；每一步各自兜底。
    private func teardownLocked() {
        teardownService()
        if let server = commandServer {
            try? server.close()
            commandServer = nil
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

    /// `LibboxSetup` 与 stderr 重定向每个进程只做一次（多次 setup 会让旧 service 的资源残留）。
    private static func processSetupOnce() throws {
        if processInitialized { return }
        do {
            try FileManager.default.createDirectory(at: ProfilePathResolver.runtimeWorkingDirectory, withIntermediateDirectories: true)
        } catch {
            throw KernelStartFailure(code: .startService, message: "cannot create working dir: \(error.localizedDescription)")
        }
        LibboxSetup(
            ProfilePathResolver.sharedContainer.relativePath,
            ProfilePathResolver.runtimeWorkingDirectory.relativePath,
            ProfilePathResolver.cacheDirectory.relativePath,
            false
        )
        var redirectError: NSError?
        LibboxRedirectStderr(
            ProfilePathResolver.cacheDirectory.appendingPathComponent("stderr.log").relativePath, &redirectError
        )
        processInitialized = true
    }

    private static func encode(_ reply: ExtensionReply) -> Data? {
        try? JSONEncoder().encode(reply)
    }

    // MARK: - 日志

    /// 写一行到命令服务器的日志流（Runner 消费），没有命令服务器时落到 NSLog。
    func forwardKernelLine(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(message)
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
