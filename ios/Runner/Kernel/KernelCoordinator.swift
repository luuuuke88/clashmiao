//
//  KernelCoordinator.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  进程级连接协调器的「命令层外壳」（B spec §3；iOS 设计 §4.2）。
//
//  所有状态变化都发生在一条串行命令队列上、同步完成、永不阻塞：
//    事件 → `CoordinatorCore`（纯状态机）→ 动作 → 本类在命令队列上执行
//    （投递 `KernelExecutor` 任务、设定时器、持久化……）→ 结果当作新事件再喂回核心。
//  Pigeon 回调（主线程）只投递或 `sync` 取回执，不直接改状态。
//

import Foundation

enum SelectResult: Equatable {
    case ok
    /// 期望的 attempt 已不是正在运行的内核实例：没有写入任何东西（B spec §10.7）。
    case stale(String)
    case failed(String)
}

/// 定时器能力，测试里换成手动推进的实现。
protocol CoordinatorScheduler: AnyObject {
    /// 同一 slot 的定时器互相替换。`fire` 在命令队列上调用。
    func schedule(slot: String, delayMs: Int64, _ fire: @escaping () -> Void)
    func cancel(slot: String)
}

/// 基于墙钟的定时器：Runner 被挂起（含设备休眠）期间不走的单调时钟会让 30 s 超时无限期推迟，
/// 墙钟在恢复后立即触发已过期的定时器。
final class DispatchScheduler: CoordinatorScheduler {
    private let queue: DispatchQueue
    private var timers: [String: DispatchSourceTimer] = [:]

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func schedule(slot: String, delayMs: Int64, _ fire: @escaping () -> Void) {
        cancel(slot: slot)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: .now() + .milliseconds(Int(delayMs)), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.timers[slot] = nil
            fire()
        }
        timers[slot] = timer
        timer.resume()
    }

    func cancel(slot: String) {
        timers.removeValue(forKey: slot)?.cancel()
    }
}

final class KernelCoordinator {
    private let queue: DispatchQueue
    private static let queueKey = DispatchSpecificKey<Void>()

    private let core: CoordinatorCore
    private let adapter: TunnelAdapter
    private let store: KernelStore
    private let executor: KernelExecutor
    private let scheduler: CoordinatorScheduler
    private let persistQueue = DispatchQueue(label: "com.clashmiao.kernel.persist")
    private let logSink: (String) -> Void

    private var isReady = false
    private var readyWaiters: [() -> Void] = []
    private var published: KernelSnapshot?
    private var listeners: [Int: (KernelSnapshot) -> Void] = [:]
    private var nextListenerId = 0

    /// 选择栅栏：已就绪（started）实例的 attempt，否则为空。命令队列在**执行任何动作之前**更新它，
    /// 所以派发重载 / 回收任务之前它已经清空；执行层上的写入据此复查。
    private let fenceLock = NSLock()
    private var liveAttempt: Int64?

    init(
        adapter: TunnelAdapter,
        store: KernelStore,
        builder: ConfigBuilding,
        scheduler: ((DispatchQueue) -> CoordinatorScheduler)? = nil,
        epoch: String = UUID().uuidString,
        config: CoordinatorCore.Config = CoordinatorCore.Config(),
        queue: DispatchQueue = DispatchQueue(label: "com.clashmiao.kernel.command"),
        log: @escaping (String) -> Void = { NSLog("[ClashMiao] %@", $0) }
    ) {
        self.queue = queue
        queue.setSpecific(key: Self.queueKey, value: ())
        self.adapter = adapter
        self.store = store
        self.logSink = log
        self.scheduler = scheduler?(queue) ?? DispatchScheduler(queue: queue)
        self.executor = KernelExecutor(adapter: adapter, store: store, builder: builder, log: log)
        self.core = CoordinatorCore(
            epoch: epoch, config: config,
            storedSpec: store.loadedSpec, storedSpecKnown: store.loadedKnown
        )
        adapter.observeStatus { [weak self] _ in self?.resync() }
        resyncNow()
    }

    // MARK: - 就绪门

    /// 管理器已加载、隧道事实已读入核心：之后才允许向 Dart 发布快照（绝不先发默认 stopped 让 Dart 当权威值）。
    func markReady() {
        async {
            self.resyncNow()
            self.isReady = true
            let waiters = self.readyWaiters
            self.readyWaiters = []
            waiters.forEach { $0() }
        }
    }

    /// `ready` 后在命令队列上调用 `body`；超时则以 `false` 调用（只会调用一次）。
    func whenReady(timeout: TimeInterval, _ body: @escaping (Bool) -> Void) {
        async {
            if self.isReady { body(true); return }
            var done = false
            let finish: (Bool) -> Void = { ok in
                if done { return }
                done = true
                body(ok)
            }
            self.readyWaiters.append { finish(true) }
            self.queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    // MARK: - 查询

    var snapshot: KernelSnapshot { onQueue { core.snapshot } }

    /// 订阅快照变化（命令队列回调）。订阅时立即推送当前值。返回取消函数。
    func observeSnapshot(_ listener: @escaping (KernelSnapshot) -> Void) -> () -> Void {
        onQueue {
            nextListenerId += 1
            let id = nextListenerId
            listeners[id] = listener
            listener(core.snapshot)
            return { [weak self] in self?.queue.async { self?.listeners[id] = nil } }
        }
    }

    // MARK: - 请求

    /// Dart 的带序号请求。回执同步返回，只表示入队 / 被拒绝。不得在命令队列上调用。
    func request(epoch: String?, seq: Int64?, desired: Desired, launch: LaunchSpec?, reason: String = "") -> Receipt {
        onQueue {
            var receipt: Receipt?
            dispatch { core.onRequest(epoch: epoch, seq: seq, desired: desired, launch: launch, reason: reason).also { receipt = $0.receipt } }
            return receipt ?? Receipt(accepted: true, reason: nil, epoch: core.epoch, appliedSeq: core.snapshot.appliedSeq)
        }
    }

    func acknowledgeReplay(_ attempt: Int64) {
        async { self.dispatch { self.core.onAckReplay(attempt) } }
    }

    /// `resetTunnel`：对同一配置强制重载一次（仅 desired=on 且已就绪时有意义）。
    func requestReload(_ src: Source) {
        async { self.dispatch { self.core.onReloadRequested(src) } }
    }

    func networkResolved(_ handle: Int64) {
        async { self.dispatch { self.core.onNetworkResolved(handle) } }
    }

    /// 重新读取隧道事实（回到前台、状态通知、管理器加载完成时调用）。Runner 被挂起期间会错过事件，
    /// 核心不依赖事件不丢，只依赖每次都能重新推导。
    func resync() {
        async { self.resyncNow() }
    }

    private func resyncNow() {
        let status = adapter.currentStatus
        let report = store.readExtensionState()
        dispatch { core.onTunnelStatus(status, report: report) }
    }

    /// 手选出站（B spec §10.7）。`expectedAttempt` 非空时，校验与写入都绑定到该 attempt 的内核实例：
    ///  1. 命令队列：该 attempt 必须是当前已就绪的实例，否则立即 stale；
    ///  2. 写入在执行层队列上与生命周期任务串行，执行前再按栅栏复查——期间若已为该实例派发回收 / 重载，
    ///     栅栏已清空，返回 stale 且不写入。新实例永远不会收到旧 attempt 的写入。
    /// `done` 恰好一次，在命令队列上回调。
    func selectOutbound(group: String, outbound: String, expectedAttempt: Int64?, done: @escaping (SelectResult) -> Void) {
        async {
            var target: (sessionId: String, generation: Int)?
            if let expected = expectedAttempt {
                guard let live = self.core.liveInstance, live.attempt == expected else {
                    done(.stale(self.staleMessage(expected)))
                    return
                }
                target = (live.sessionId, live.generation)
            }
            self.executor.runSerialized {
                let result: SelectResult
                if let expected = expectedAttempt, self.fence() != expected {
                    result = .stale(self.staleMessage(expected))
                } else {
                    result = self.sendSelect(group, outbound, target)
                }
                self.queue.async { done(result) }
            }
        }
    }

    /// 真正的校验与写入在扩展里（与 service 替换同一条串行队列）；这里只是发消息。
    private func sendSelect(_ group: String, _ outbound: String, _ target: (sessionId: String, generation: Int)?) -> SelectResult {
        let request = ExtensionRequest(
            op: .select, group: group, outbound: outbound,
            sessionId: target?.sessionId, generation: target?.generation
        )
        do {
            let reply = try adapter.sendMessage(request, timeout: Self.selectTimeout)
            if reply.ok { return .ok }
            if reply.isStale { return .stale(reply.message ?? "stale") }
            return .failed(reply.message ?? "select failed")
        } catch {
            return .failed((error as? TunnelAdapterError)?.message ?? error.localizedDescription)
        }
    }

    static let selectTimeout: TimeInterval = 10

    private func fence() -> Int64? {
        fenceLock.lock(); defer { fenceLock.unlock() }
        return liveAttempt
    }

    private func staleMessage(_ expected: Int64) -> String {
        "attempt \(expected) is not the running instance (live=\(fence().map(String.init) ?? "none"))"
    }

    // MARK: - 派发与动作执行

    private func dispatch(_ supplier: () -> CoreStep) {
        let step = supplier()
        let s = core.snapshot
        fenceLock.lock()
        liveAttempt = s.status == .started ? s.attempt : nil
        fenceLock.unlock()
        execute(step.effects)
        publishIfChanged()
    }

    private func publishIfChanged() {
        let s = core.snapshot
        if s == published { return }
        published = s
        logSink("snapshot \(s.logLine())")
        for l in listeners.values { l(s) }
    }

    private func execute(_ effects: [Effect]) {
        for e in effects {
            switch e {
            case .log(let line):
                logSink("core: \(line)")
            case .runConnect(let token, let spec, let launchId):
                executor.submitConnect(token: token, spec: spec, launchId: launchId, onStep: onStep, onDone: onDone)
            case .runReload(let token, let spec, let launchId, let sessionId):
                executor.submitReload(token: token, spec: spec, launchId: launchId, sessionId: sessionId, onStep: onStep, onDone: onDone)
            case .runTeardown(let token):
                executor.submitTeardown(token: token, onStep: onStep, onDone: onDone)
            case .cancelJob(let token):
                executor.cancel(token: token)
            case .setTimer(let key, let delayMs):
                scheduler.schedule(slot: key.slot, delayMs: delayMs) { [weak self] in
                    guard let self else { return }
                    // 先读事实再裁决 deadline：恢复后已过期的超时不能误杀后台早已成功的启动。
                    self.resyncNow()
                    self.dispatch { self.core.onTimer(key) }
                }
            case .cancelTimer(let key):
                scheduler.cancel(slot: key.slot)
            case .persist(let desired, let spec, let serial):
                // 后台线程写盘，以返回值为准：确认落盘之前核心同时声明新旧两份路径。
                persistQueue.async { [weak self] in
                    guard let self else { return }
                    let ok = self.store.commitIntent(desired: desired, spec: spec)
                    if !ok { self.logSink("persist #\(serial) not confirmed on disk") }
                    self.queue.async { self.dispatch { self.core.onPersistResult(serial: serial, ok: ok) } }
                }
            }
        }
    }

    private var onStep: (Int64, String) -> Void {
        { [weak self] token, name in
            self?.queue.async { guard let self else { return }; self.dispatch { self.core.onJobStep(token: token, name: name) } }
        }
    }

    private var onDone: (Int64, JobResult) -> Void {
        { [weak self] token, result in
            self?.queue.async {
                guard let self else { return }
                self.dispatch { self.core.onJobFinished(token: token, result: result) }
                self.resyncNow() // 提交之后隧道的实际状态以系统为准
            }
        }
    }

    // MARK: - 队列工具

    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil { return body() }
        return queue.sync(execute: body)
    }

    private func async(_ body: @escaping () -> Void) {
        queue.async(execute: body)
    }
}

private extension CoreStep {
    func also(_ body: (CoreStep) -> Void) -> CoreStep {
        body(self)
        return self
    }
}
