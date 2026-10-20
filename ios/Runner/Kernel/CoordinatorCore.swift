//
//  CoordinatorCore.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  连接生命周期协调器的「命令层」状态机（B spec §3、§10；iOS 设计 §4）。
//
//  纯 Swift：输入「事件」（公开的 `onXxx` 方法），输出「动作」（`Effect` 列表）和新的
//  `KernelSnapshot`。它不碰线程、不碰 NetworkExtension、不读写文件、不读时钟——
//  `KernelCoordinator` 把动作翻译成真正的副作用（投递执行层任务、设定时器、持久化……），
//  再把结果当作新的事件喂回来。时间只是「动作（setTimer）+ 事件（onTimer）」，所以单测不需要真实时钟。
//
//  与 Android `CoordinatorCore` 的对应关系：骨架一致（单一入口 `reconcile`、每种动作由标志位保证只发一次、
//  请求归属 Owner / 启动序列 Exec / 执行层任务 Job 带不可变归属、只有仍属于当前请求的序列才能写
//  failure 并把 desired 置 off、配置引用由原生在快照里声明）。差异只有「承载内核的东西」：
//  Android 是多个 Service 实例（startId、退休、VPN 授权对话框），iOS 是**一条隧道会话**，
//  所以换成隧道事实（`TunnelStatus` + 扩展写盘的 `ExtensionState`）与 Connect / Reload / Teardown 三类任务。
//
//  隧道的「就绪」不是任务返回，而是事实：NE 状态 connected 且扩展 state 为 running 且 launchId 匹配。
//  所有隧道输入都是电平触发（外壳每次读当前 status 与 state 文件）；Runner 被挂起时错过的事件由外壳的
//  `resync` 重新喂入，核心不依赖事件不丢。
//
//  三个标识（iOS 设计 §3）：launchId = Runner 操作 ID；sessionId = 扩展实例 ID；generation = 内核 service 代次。
//  attempt 严格按真实 generation / session 变化分配，不靠 `reasserting` 猜（`clearDNSCache` 也会触发它）。
//

import Foundation

final class CoordinatorCore {

    struct Config {
        /// 启动超时（含系统 VPN 授权弹窗与隧道拉起），B spec §2：30 s。
        var startTimeoutMs: Int64 = 30_000
        /// 单个阻塞步骤 / 停止 / 重载回执超过该时长判定失联，B spec §3：20 s。
        var stepWatchdogMs: Int64 = 20_000
        /// 网络切换去抖。
        var networkDebounceMs: Int64 = 1_000
        /// 启动被放弃后，迟到的 connecting / connected 不被当作外部启动的时间窗。
        var adoptGuardMs: Int64 = 10_000
        /// 网络切换后是否自行重载。iOS 默认关：扩展内内核自己跟随默认网络，
        /// 真机若证明切网后连接不恢复再打开。
        var reloadOnNetworkChange = false
    }

    /// 不计入 20 s 看门狗的步骤：系统授权弹窗由用户操作，由 30 s 启动超时统一兜底。
    static let authorizeStep = "authorize"

    // MARK: - 内部类型

    /// 请求归属：内部单调 id（外部入口也各有一个）+ Dart 序号（外部入口为空）。
    private struct Owner: Equatable {
        let id: Int64
        let seq: Int64?
    }

    /// 一次启动序列：Connect 或 Reload + 等待就绪。`owner` 不可变：意图一变就是新请求、新序列。
    private final class Exec {
        let token: Int64
        let owner: Owner
        /// 序列第一次真正动手时才分配 attempt。
        var attempt: Int64?
        var isReload = false
        init(token: Int64, owner: Owner) {
            self.token = token
            self.owner = owner
        }
    }

    private enum JobKind { case connect, reload, teardown }

    private final class Job {
        let kind: JobKind
        let token: Int64
        let owner: Owner
        /// 派发它的启动序列；Teardown 与请求无关时为空。
        let execToken: Int64?
        let specRev: Int64
        let specPath: String?
        var cancelRequested = false
        var stepSerial: Int64 = 0
        var stepName = ""
        var unresponsive = false
        init(kind: JobKind, token: Int64, owner: Owner, execToken: Int64?, specRev: Int64, specPath: String?) {
            self.kind = kind
            self.token = token
            self.owner = owner
            self.execToken = execToken
            self.specRev = specRev
            self.specPath = specPath
        }
    }

    // MARK: - 状态

    let epoch: String
    private let config: Config
    private let makeLaunchId: () -> String

    // 快照字段
    private var attempt: Int64 = 0
    private var desired: Desired = .off
    private var source: Source = .system
    private var appliedSeq: Int64 = 0
    private var activeRev: Int64?
    private var lastFailure: KernelFailure?
    private var replayNeeded = false

    /// 已确认在磁盘上的持久化 spec 路径；之后只由成功的 `onPersistResult` 更新。
    private var storedPath: String?
    private var storedKnown: Bool
    /// 持久化 spec 本身（外部启动 / 冷启动挂接时作为 fallback）。
    private var storedSpec: LaunchSpec?
    /// 已发出、尚未确认落盘的持久化（serial → spec 路径）。失败的也留着：内存里已是新值，
    /// 之后任何一次整文件写盘都可能把它带到磁盘上；只有更晚的一次确认成功才能清掉它。
    private var unconfirmedStored: [(serial: Int64, path: String)] = []
    private var persistSerial: Int64 = 0

    /// 运行中内核所用 spec 的配置文件路径。
    private var activePath: String?

    private(set) var snapshot: KernelSnapshot

    /// 已就绪（started）实例的标识，供手选出站带给扩展做最终校验；非 started 为 nil。
    var liveInstance: (attempt: Int64, sessionId: String, generation: Int)? {
        guard snapshot.status == .started, let session = knownSession else { return nil }
        return (snapshot.attempt, session, knownGeneration)
    }

    // 意图
    private var spec: LaunchSpec?
    private var owner = Owner(id: 0, seq: nil)
    private var ownerIds: Int64 = 0
    /// 已为该请求写过 failure（之后不再用别的失败覆盖它）。
    private var failedOwner: Int64?
    private var reloadRequested = false

    // 事实
    private var tunnel: TunnelStatus = .disconnected
    private var lastReport: ExtensionState?
    /// 我们派发了 Connect、隧道还没到 connected / disconnected。
    /// 它是「这是我自己的启动，不是外部启动」的唯一依据。
    private var launching = false
    /// Connect 任务已确认提交 `startVPNTunnel`。提交之前到达的 disconnected 事件只是噪声，不能算启动失败。
    private var launchSubmitted = false
    /// 一次启动被放弃（提交了却迟迟不可见）之后的保护窗：窗口内迟到的启动属于我们，不是外部启动。
    private var adoptGuard = false
    /// 保护窗内是否已经看到过隧道的实际活动。启动被放弃时隧道本就是 down，紧随其后的 resync 读到的仍是同一个
    /// down，不能据此认为保护窗该结束——只有「看到过活动之后又 down」才算这次迟到的启动已经收场。
    private var guardSawActive = false
    /// 派发当前这次 Connect 的请求归属。启动的失败 / 下线只属于派发它的请求；之后被更新请求取代，
    /// 旧启动的退场只负责收尾，不得把失败记到新请求头上。
    private var launchOwner: Owner?
    /// 已知的扩展实例与 service 代次。
    private var knownSession: String?
    private var knownGeneration = 0
    /// 接管了一个 revision 与持久化 spec 对不上的运行内核：不知道它读的是哪份 `runtime-*.json`，
    /// 快照的 `retainedConfigPaths` 因此报未知，直到下一次自有启动 / 重载。
    private var runningRefUnknown = false
    private var currentLaunchId: String?
    /// 已提交 `stopVPNTunnel`、隧道还没到 disconnected。
    private var stopSubmitted = false
    private var job: Job?
    private var exec: Exec?
    private var tokens: Int64 = 0

    // 网络
    private var netBaseline: Int64?
    private var netPending: Int64?
    private var netSerial: Int64 = 0

    private var out: [Effect] = []

    // MARK: - 构造

    init(
        epoch: String,
        config: Config = Config(),
        storedSpec: LaunchSpec? = nil,
        storedSpecKnown: Bool = true,
        makeLaunchId: @escaping () -> String = { UUID().uuidString }
    ) {
        self.epoch = epoch
        self.config = config
        self.makeLaunchId = makeLaunchId
        self.storedSpec = storedSpec
        self.storedPath = storedSpec?.runtimeConfigPath
        self.storedKnown = storedSpecKnown
        self.snapshot = KernelSnapshot(
            epoch: epoch,
            version: 1,
            status: .stopped,
            attempt: 0,
            desired: .off,
            source: .system,
            appliedSeq: 0,
            activeConfigRevision: nil,
            lastFailure: nil,
            selectionsReplayNeeded: false,
            retainedConfigPaths: Self.retainedOf(storedSpecKnown, [storedSpec?.runtimeConfigPath])
        )
    }

    // MARK: - 事件入口

    /// Dart 的带序号请求（B spec §10.1）。`epoch` / `seq` 为空 = 内部转发，不参与序号校验也不推进 appliedSeq。
    func onRequest(
        epoch: String?,
        seq: Int64?,
        desired newDesired: Desired,
        launch: LaunchSpec?,
        reason: String = ""
    ) -> CoreStep {
        step {
            if let epoch, epoch != self.epoch {
                log("request seq=\(seq.map(String.init) ?? "nil") rejected: wrongEpoch (got=\(epoch.prefix(8)))")
                return Receipt(accepted: false, reason: .wrongEpoch, epoch: self.epoch, appliedSeq: appliedSeq)
            }
            if let seq, seq <= appliedSeq {
                // 过期请求：不改变任何状态。
                log("request seq=\(seq) rejected: stale (appliedSeq=\(appliedSeq))")
                return Receipt(accepted: false, reason: .stale, epoch: self.epoch, appliedSeq: appliedSeq)
            }
            if let seq { appliedSeq = seq }
            log("request seq=\(seq.map(String.init) ?? "nil") desired=\(newDesired.rawValue) reason=\(reason)")
            let effective = launch ?? spec
            if newDesired == .on, effective == nil {
                // 协议约定 on 必带 LaunchSpec（桥层已校验）；缺失且没有可沿用的 spec，按空配置失败。
                claim(.app, seq)
                fail(.emptyConfiguration, "missing launch spec", attempt)
            } else {
                applyIntent(newDesired, effective, .app, seq)
            }
            return Receipt(accepted: true, reason: nil, epoch: self.epoch, appliedSeq: appliedSeq)
        }
    }

    /// 外部入口（系统设置里开 / 关 VPN 被观察到）。on 时用 `fallbackSpec`（持久化的最近 spec）。
    func onExternal(_ src: Source, desired newDesired: Desired, fallbackSpec: LaunchSpec?) -> CoreStep {
        step {
            externalIntent(src, newDesired, fallbackSpec)
            return nil
        }
    }

    /// 隧道事实：`NEVPNStatusDidChange`、外壳的 `resync`、冷启动首次读取。
    /// `report` 是扩展最近写下的 `extension-state.json`（可能为空或属于上一次启动）。
    func onTunnelStatus(_ status: TunnelStatus, report: ExtensionState?) -> CoreStep {
        step {
            let previous = tunnel
            tunnel = status
            lastReport = report
            handleTunnel(previous: previous, status: status, report: report)
            return nil
        }
    }

    /// 非本请求的重载请求（`resetTunnel`）。
    func onReloadRequested(_ src: Source) -> CoreStep {
        step {
            if desired == .on, spec != nil, exec == nil, activeRev != nil, job == nil {
                log("reload requested by \(src.rawValue)")
                source = src
                reloadRequested = true
            } else {
                log("reload request ignored (desired=\(desired.rawValue), starting=\(exec != nil))")
            }
            return nil
        }
    }

    /// 默认网络句柄变化（`NWPathMonitor`）。按句柄去重、吸收初始事件，去抖后（可选）重载。
    func onNetworkResolved(_ handle: Int64) -> CoreStep {
        step {
            let settled = desired == .on && spec != nil && activeRev != nil && exec == nil && job == nil
            if !settled {
                // 启动中 / 未运行：只记基线（arm 之后系统会立刻补发一次当前网络）。
                netBaseline = handle
                netPending = nil
            } else if netBaseline == nil {
                netBaseline = handle
            } else if handle == netBaseline {
                netPending = nil
            } else {
                netPending = handle
                netSerial += 1
                if config.reloadOnNetworkChange {
                    out.append(.setTimer(TimerKey(.netDebounce, serial: netSerial), delayMs: config.networkDebounceMs))
                } else {
                    // 只更新基线；`/network` 事件由外壳单独推给 Dart。
                    netBaseline = handle
                    netPending = nil
                }
            }
            return nil
        }
    }

    /// 第 `serial` 次持久化的落盘结果。成功：它和更早的未确认项全部撤下；失败：什么都不撤。
    func onPersistResult(serial: Int64, ok: Bool) -> CoreStep {
        step {
            guard ok else {
                log("persist #\(serial) not confirmed on disk; keep declaring old and new spec paths")
                return nil
            }
            // 一次写盘写出整份内存内容：其中的 spec 是不晚于本次的最后一次写入。
            if let path = unconfirmedStored.last(where: { $0.serial <= serial })?.path {
                storedPath = path
                storedKnown = true
            }
            unconfirmedStored.removeAll { $0.serial <= serial }
            return nil
        }
    }

    /// Dart 确认某 attempt 的手选重放完成（幂等；attempt 不是当前值则忽略）。
    func onAckReplay(_ ackAttempt: Int64) -> CoreStep {
        step {
            if ackAttempt == attempt { replayNeeded = false }
            return nil
        }
    }

    /// 执行层任务进入一个新的阻塞步骤（重新计 20 s 看门狗）。
    func onJobStep(token: Int64, name: String) -> CoreStep {
        step {
            guard let j = job, j.token == token else { return nil }
            j.stepSerial += 1
            j.stepName = name
            j.unresponsive = false
            if name == Self.authorizeStep {
                out.append(.cancelTimer(TimerKey(.watchdog, subject: token)))
            } else {
                out.append(.setTimer(
                    TimerKey(.watchdog, subject: token, serial: j.stepSerial), delayMs: config.stepWatchdogMs
                ))
            }
            return nil
        }
    }

    func onJobFinished(token: Int64, result: JobResult) -> CoreStep {
        step {
            guard let j = job, j.token == token else {
                log("job result dropped (token=\(token) result=\(result))")
                return nil
            }
            job = nil
            out.append(.cancelTimer(TimerKey(.watchdog, subject: token)))
            // 仍属于当前请求的启动序列；为空 = 过时的执行，只剩回收自身资源的资格。
            let e = exec.flatMap { $0.token == j.execToken ? $0 : nil }
            switch (j.kind, result) {
            case (.teardown, _):
                // stopVPNTunnel 已提交（或隧道本已不在）；真正停止等 disconnected 事件。
                // 隧道在我们看来已经不在了：没有 disconnected 事件可等。否则一直保持，直到 handleDown 清除。
                if tunnel.isDown { stopSubmitted = false }
            case (.connect, .launched):
                launchSubmitted = true
            case (.reload, .reloaded(let sessionId, let generation)):
                activeRev = j.specRev
                activePath = j.specPath
                replayNeeded = true
                reloadRequested = false
                runningRefUnknown = false
                knownSession = sessionId
                knownGeneration = generation
            case (.connect, .abandoned(let code, let message)):
                launching = false
                launchSubmitted = false
                adoptGuard = true
                guardSawActive = false
                out.append(.setTimer(TimerKey(.adoptGuard), delayMs: config.adoptGuardMs))
                if let e { failExec(e, code, message) }
            case (.connect, .failed(let code, let message)), (.reload, .failed(let code, let message)):
                if j.kind == .connect { launching = false; launchSubmitted = false }
                if let e {
                    failExec(e, code, message)
                } else {
                    log("stale \(j.kind) failure dropped: \(code.rawValue) (owner seq=\(j.owner.seq.map(String.init) ?? "nil"))")
                }
            case (.connect, .cancelled), (.reload, .cancelled):
                if j.kind == .connect { launching = false; launchSubmitted = false }
                // 取消点都在提交之前：没有东西要回收。当前序列若还在，说明新请求又要 on 了，
                // 由 reconcile 重新派发，不是失败。
                _ = e
            default:
                log("unexpected job result \(result) for \(j.kind)")
            }
            return nil
        }
    }

    func onTimer(_ key: TimerKey) -> CoreStep {
        step {
            switch key.kind {
            case .startTimeout:
                guard let e = exec, e.token == key.subject else { return nil }
                failExec(e, .startTimeout, "start timed out")
            case .watchdog:
                guard let j = job, j.token == key.subject, j.stepSerial == key.serial, !j.unresponsive else { return nil }
                j.unresponsive = true
                log("watchdog: step '\(j.stepName)' blocked > \(config.stepWatchdogMs)ms (owner seq=\(j.owner.seq.map(String.init) ?? "nil"))")
                let e = exec
                if desired == .off {
                    // 当前请求是停止：它的完成被卡死的执行层挡住，这是它自己的结果（状态如实保持 stopping）。
                    if failedOwner != owner.id {
                        lastFailure = KernelFailure(
                            code: .kernelUnresponsive, message: "blocked in \(j.stepName)",
                            attempt: attempt, seq: owner.seq
                        )
                        failedOwner = owner.id
                    }
                } else if let e, j.execToken == e.token {
                    failExec(e, .kernelUnresponsive, "blocked in \(j.stepName)")
                } else {
                    // 过时的执行卡住：不改 desired、不写 failure；当前请求由它自己的 30 s 启动超时兜底。
                    log("stale job unresponsive; request seq=\(owner.seq.map(String.init) ?? "nil") keeps its own start timeout")
                }
            case .adoptGuard:
                adoptGuard = false
                guardSawActive = false
            case .stopWatchdog:
                guard key.subject == stopWatchSerial, stopSubmitted, !tunnel.isDown else { return nil }
                log("stop watchdog: tunnel not disconnected > \(config.stepWatchdogMs)ms")
                if desired == .off, failedOwner != owner.id {
                    lastFailure = KernelFailure(
                        code: .kernelUnresponsive, message: "tunnel did not stop",
                        attempt: attempt, seq: owner.seq
                    )
                    failedOwner = owner.id
                }
            case .netDebounce:
                guard key.serial == netSerial else { return nil }
                let pending = netPending
                netPending = nil
                if let pending, pending != netBaseline, desired == .on, spec != nil, activeRev != nil, exec == nil, job == nil {
                    log("network changed -> reload")
                    netBaseline = pending
                    reloadRequested = true
                }
            }
            return nil
        }
    }

    // MARK: - 隧道事实推导（iOS 设计 §4.1 的矩阵）

    /// 提交 Connect 时记下它将要跑的 spec；隧道到 connected 后才晋升为 `activePath` / `activeRev`。
    private var pendingActivePath: String?
    private var pendingActiveRev: Int64?
    private var stopWatchSerial: Int64 = 0

    private func handleTunnel(previous: TunnelStatus, status: TunnelStatus, report: ExtensionState?) {
        if adoptGuard, status == .connecting || status == .connected || status == .reasserting {
            guardSawActive = true
        }
        switch status {
        case .connected:
            handleConnected(report)
        case .connecting:
            // 不是我们提交的、也不在预期下线中：外部启动（系统设置里手动打开 / Runner 被杀前的会话）。
            if !launching, !stopSubmitted, !adoptGuard, job == nil, desired == .off {
                log("external start observed (connecting)")
                adoptIntent()
            }
        case .reasserting:
            break // 只影响显示（computeStatus）；attempt 只跟 generation 走
        case .disconnecting:
            // 设置里关 VPN：扩展的 stopTunnel 已把 state 写成 stopped，不必等 disconnected 才反应。
            if desired == .on, activeRev != nil, !stopSubmitted, let r = report, r.phase == .stopped,
               r.sessionId == knownSession, !StopReasonClass.isFailure(r.stopReason) {
                log("system stop observed (disconnecting, stopReason=\(r.stopReason.map(String.init) ?? "nil"))")
                applyIntent(.off, nil, .system, nil)
            }
        case .disconnected, .invalid:
            handleDown(report)
        }
    }

    private func handleConnected(_ report: ExtensionState?) {
        guard let r = report, r.phase == .running else {
            // 隧道已 connected 但扩展还没（或不再）声明 running：内核是否起来未确认，保持 starting，
            // 由 resync / 启动超时收口。
            log("connected but extension state not running (phase=\(report?.phase.rawValue ?? "nil"))")
            return
        }
        if launching {
            guard r.launchId == currentLaunchId else {
                log("connected with foreign launchId; waiting")
                return
            }
            launching = false
            launchSubmitted = false
            activeRev = r.revision ?? pendingActiveRev
            activePath = pendingActivePath
            runningRefUnknown = false
            replayNeeded = true
            knownSession = r.sessionId
            knownGeneration = r.generation
            log("kernel up (own launch) rev=\(activeRev.map(String.init) ?? "nil") gen=\(r.generation)")
            return
        }
        if job?.kind == .reload { return } // 本请求的重载由回执裁决
        if activeRev != nil, let known = knownSession {
            if r.sessionId != known {
                // 扩展换了实例而我们没看到下线：重新记账，等同接管。
                log("extension session replaced (\(known.prefix(8)) -> \(r.sessionId.prefix(8)))")
                rebase(r)
            } else if r.generation > knownGeneration {
                // 内核被重载过，不是我们的 Reload（含后台完整发生、没看到 reasserting 的情况）。
                log("external reload observed gen \(knownGeneration) -> \(r.generation)")
                rebase(r)
            }
            return
        }
        if activeRev == nil, !stopSubmitted, job == nil, !(adoptGuard && desired == .off) {
            adoptRunning(r)
        }
    }

    /// 同一/新的扩展实例里内核被重新创建：attempt +1，要求重放手选。
    private func rebase(_ r: ExtensionState) {
        attempt += 1
        if let e = exec { e.attempt = attempt }
        activeRev = r.revision
        let matches = storedSpec?.configRevision == r.revision
        activePath = matches ? storedSpec?.runtimeConfigPath : nil
        runningRefUnknown = !matches
        replayNeeded = true
        knownSession = r.sessionId
        knownGeneration = r.generation
        currentLaunchId = r.launchId
    }

    /// 外部（系统）把隧道打开了：把它当作一个新的 on 请求受理，沿用持久化的 spec（可能为空）。
    private func adoptIntent() {
        claim(.system, nil)
        killExec()
        desired = .on
        spec = spec ?? storedSpec
        persist()
    }

    /// 接管一个已在运行的内核（冷启动挂接 / 外部启动完成）。扩展自己持有全部运行所需（intent + final 配置），
    /// 所以即使 Runner 没有持久化的 spec 也能接管：此时 `spec` 为空，等 Dart 的请求带来 spec 再比较 revision。
    private func adoptRunning(_ r: ExtensionState) {
        if desired == .off { adoptIntent() }
        // 运行中的内核不是我们记着的那份 spec：别把它重载成一份陈旧的 spec，等 Dart 的请求带来新的再比较。
        if let sp = spec, sp.configRevision != r.revision { spec = nil }
        if let e = exec { ensureAttempt(e) } else { attempt += 1 }
        activeRev = r.revision
        let matches = storedSpec?.configRevision == r.revision
        activePath = matches ? storedSpec?.runtimeConfigPath : nil
        runningRefUnknown = !matches
        replayNeeded = true
        knownSession = r.sessionId
        knownGeneration = r.generation
        currentLaunchId = r.launchId
        log("adopted running kernel rev=\(r.revision.map(String.init) ?? "nil") gen=\(r.generation)")
    }

    private func handleDown(_ report: ExtensionState?) {
        // 我们的 Connect 还没提交到系统：此刻的 disconnected 只是启动前的初始状态，不是启动失败。
        if launching, !launchSubmitted { return }
        let expected = stopSubmitted
        let wasUp = activeRev != nil || launching
        let wasLaunching = launching
        // state 属于当前这条隧道会话 / 当前操作吗？
        let relevant: ExtensionState? = report.flatMap {
            ($0.sessionId == knownSession || $0.launchId == currentLaunchId || currentLaunchId == nil) ? $0 : nil
        }
        stopSubmitted = false
        out.append(.cancelTimer(TimerKey(.stopWatchdog)))
        if adoptGuard, guardSawActive {
            adoptGuard = false
            guardSawActive = false
            out.append(.cancelTimer(TimerKey(.adoptGuard)))
        }
        let launchBelongsToCurrent = launchOwner == nil || launchOwner == owner
        guard desired == .on, wasUp, !expected else {
            // 预期中的下线 / 本来就不在 / desired 已是 off：只是收尾，不改任何意图。
            kernelGone()
            if desired == .off {
                netBaseline = nil
                netPending = nil
            }
            return
        }
        // 隧道在我们不要它消失的时候消失了。
        kernelGone()
        if wasLaunching, !launchBelongsToCurrent {
            // 被更新请求取代的旧启动退场了：它的失败不是新请求的失败，收尾后由 reconcile 为新请求重新启动。
            log("superseded launch ended (\(relevant?.phase.rawValue ?? "no state")); current request continues")
            return
        }
        guard let r = relevant else {
            fail(wasLaunching ? .startService : .kernelExited,
                 wasLaunching ? "tunnel stopped during start" : "tunnel ended unexpectedly", attempt)
            return
        }
        switch r.phase {
        case .failed:
            fail(r.code ?? .startService, r.message ?? "tunnel failed", attempt)
        case .stopped:
            if StopReasonClass.isFailure(r.stopReason) {
                fail(wasLaunching ? .startService : .kernelExited,
                     "tunnel stopped by system (reason \(r.stopReason.map(String.init) ?? "?"))", attempt)
            } else {
                // 用户 / 系统在设置里关了 VPN，或另一个 VPN 抢占：不是失败。
                log("system stop observed (disconnected, stopReason=\(r.stopReason.map(String.init) ?? "nil"))")
                applyIntent(.off, nil, .system, nil)
            }
        case .running, .starting:
            // 没有终态记录：扩展被系统强杀（多为内存超限），或启动中途死亡。
            fail(wasLaunching ? .startService : .kernelExited,
                 "tunnel process ended unexpectedly (possibly out of memory)", attempt)
        }
    }

    // MARK: - 意图

    /// 受理一个新请求：它取代之前的请求。
    private func claim(_ src: Source, _ seq: Int64?) {
        source = src
        ownerIds += 1
        owner = Owner(id: ownerIds, seq: seq)
    }

    private func externalIntent(_ src: Source, _ newDesired: Desired, _ fallback: LaunchSpec?) {
        log("external source=\(src.rawValue) desired=\(newDesired.rawValue)")
        if newDesired == .on {
            guard let s = spec ?? fallback else {
                claim(src, nil)
                fail(.emptyConfiguration, "no launch spec", attempt)
                return
            }
            applyIntent(.on, s, src, nil)
        } else {
            applyIntent(.off, nil, src, nil)
        }
    }

    private func applyIntent(_ newDesired: Desired, _ newSpec: LaunchSpec?, _ newSource: Source, _ seq: Int64?) {
        claim(newSource, seq)
        // 旧序列不再属于任何当前请求：撤掉它的超时；它的在途任务只剩回收自身资源的资格。
        killExec()
        switch newDesired {
        case .off:
            setDesiredOff()
            // 重发 off 且停止仍卡着：这条新请求同样被挡住，结果如实给它，并允许重新提交停止。
            if stopSubmitted, lastFailure?.code == .kernelUnresponsive {
                lastFailure = KernelFailure(code: .kernelUnresponsive, message: "tunnel did not stop", attempt: attempt, seq: seq)
                failedOwner = owner.id
                stopSubmitted = false
            } else if let j = job, j.unresponsive {
                lastFailure = KernelFailure(code: .kernelUnresponsive, message: "blocked in \(j.stepName)", attempt: attempt, seq: seq)
                failedOwner = owner.id
            }
        case .on:
            guard let s = newSpec else { return }
            let changed = desired == .off || spec != s
            spec = s
            storedSpec = s
            desired = .on
            if changed { persist() }
        }
    }

    private func setDesiredOff() {
        if desired == .off { return }
        desired = .off
        persist()
    }

    private func persist() {
        persistSerial += 1
        if let path = spec?.runtimeConfigPath { unconfirmedStored.append((persistSerial, path)) }
        out.append(.persist(desired: desired, spec: spec, serial: persistSerial))
    }

    /// 当前请求失败：写 failure（seq = 当前请求）并把 desired 置 off。
    private func fail(_ code: FailureCode, _ message: String, _ failedAttempt: Int64) {
        log("request seq=\(owner.seq.map(String.init) ?? "nil") failed: \(code.rawValue) (\(message))")
        lastFailure = KernelFailure(code: code, message: message, attempt: failedAttempt, seq: owner.seq)
        failedOwner = owner.id
        setDesiredOff()
    }

    private func failExec(_ e: Exec, _ code: FailureCode, _ message: String) {
        guard e === exec, e.owner == owner, desired == .on else {
            log("stale start failure dropped: \(code.rawValue) (\(message))")
            return
        }
        fail(code, message, e.attempt ?? attempt)
    }

    /// 运行中的内核满足当前意图。`spec` 为空只会发生在接管外部启动、尚无 Dart 请求时：没有可比较的 revision，
    /// 视为满足（Dart 的请求带着 spec 来了再比较）。
    /// 当前隧道事实确认内核在跑：系统层面 connected，且扩展 state 声明 running、属于我们记着的那个扩展实例。
    /// 缓存的 `activeRev` 只是上一次确认的结果，不能压过新读到的非 running 事实（重载中、state 缺失 / 损坏）。
    private var factsConfirmRunning: Bool {
        guard tunnel == .connected, let r = lastReport, r.phase == .running else { return false }
        return r.sessionId == knownSession
    }

    private func kernelMatchesIntent() -> Bool {
        guard desired == .on, let rev = activeRev, !stopSubmitted, factsConfirmRunning else { return false }
        guard let s = spec else { return true }
        return rev == s.configRevision
    }

    private func kernelGone() {
        activeRev = nil
        activePath = nil
        replayNeeded = false
        reloadRequested = false
        launching = false
        launchSubmitted = false
        launchOwner = nil
        runningRefUnknown = false
        knownSession = nil
        knownGeneration = 0
    }

    // MARK: - 推导

    private func reconcile() {
        cancelUselessStartJob()
        if desired == .off { reconcileOff() } else { reconcileOn() }
    }

    /// 在途 Connect / Reload 若已不能满足当前意图（off 或 revision 变了）就打取消标，
    /// 让它在下一个取消点停手；仍能满足的继续跑，结果可被新请求沿用。
    private func cancelUselessStartJob() {
        guard let j = job, j.kind != .teardown, !j.cancelRequested else { return }
        let useful = desired == .on && spec?.configRevision == j.specRev
        if !useful {
            j.cancelRequested = true
            out.append(.cancelJob(token: j.token))
        }
    }

    private func reconcileOff() {
        killExec()
        if job != nil { return }
        // 隧道还在（含正在拉起）：停掉。disconnecting 期间系统已在停，等 disconnected 事件。
        if !tunnel.isDown, tunnel != .disconnecting, !stopSubmitted {
            dispatchTeardown()
        }
    }

    private func reconcileOn() {
        if kernelMatchesIntent(), !reloadRequested {
            // 已收敛（含沿用过时执行的成功结果）：当前请求的序列到此完成。
            if let e = exec { completeExec(e) }
            return
        }
        // 没收敛：当前请求必须有自己的序列（及其 30 s 超时），哪怕执行层还被过时任务占着。
        let e: Exec
        if let existing = exec {
            e = existing
        } else {
            e = newExec()
            exec = e
        }
        if job != nil { return }

        if launching {
            ensureAttempt(e)
            return // 我们已提交的启动，等隧道事实
        }
        if stopSubmitted || tunnel == .disconnecting {
            return // 旧隧道还在停，不能抢跑 startVPNTunnel
        }
        switch tunnel {
        case .disconnected, .invalid:
            guard let s = spec else {
                fail(.emptyConfiguration, "no launch spec", e.attempt ?? attempt)
                return
            }
            dispatchConnect(e, s)
        case .connecting:
            ensureAttempt(e)
        case .reasserting:
            break // 内核正在（被扩展）重建，等它回到 connected；30 s 启动超时兜底
        case .connected:
            if activeRev != nil, factsConfirmRunning, let s = spec {
                // 内核确认在跑但 revision 不同 / 被要求重载：就地重载，不断开 VPN。
                e.isReload = true
                dispatchReload(e, s)
            } else {
                ensureAttempt(e) // 等扩展 state 声明 running（resync 会补）；30 s 启动超时兜底
            }
        case .disconnecting:
            break
        }
    }

    private func newExec() -> Exec {
        tokens += 1
        let e = Exec(token: tokens, owner: owner)
        out.append(.setTimer(TimerKey(.startTimeout, subject: e.token), delayMs: config.startTimeoutMs))
        log("exec token=\(e.token) seq=\(owner.seq.map(String.init) ?? "nil")")
        return e
    }

    private func ensureAttempt(_ e: Exec) {
        if e.attempt != nil { return }
        attempt += 1
        e.attempt = attempt
        replayNeeded = false
        log("exec token=\(e.token) attempt=\(attempt) reload=\(e.isReload)")
    }

    private func completeExec(_ e: Exec) {
        out.append(.cancelTimer(TimerKey(.startTimeout, subject: e.token)))
        exec = nil
    }

    private func dispatchConnect(_ e: Exec, _ s: LaunchSpec) {
        ensureAttempt(e)
        tokens += 1
        let j = Job(kind: .connect, token: tokens, owner: e.owner, execToken: e.token,
                    specRev: s.configRevision, specPath: s.runtimeConfigPath)
        job = j
        let launchId = makeLaunchId()
        currentLaunchId = launchId
        launching = true
        launchSubmitted = false
        launchOwner = e.owner
        pendingActivePath = s.runtimeConfigPath
        pendingActiveRev = s.configRevision
        out.append(.runConnect(token: j.token, spec: s, launchId: launchId))
        out.append(.setTimer(TimerKey(.watchdog, subject: j.token), delayMs: config.stepWatchdogMs))
    }

    private func dispatchReload(_ e: Exec, _ s: LaunchSpec) {
        ensureAttempt(e)
        tokens += 1
        let j = Job(kind: .reload, token: tokens, owner: e.owner, execToken: e.token,
                    specRev: s.configRevision, specPath: s.runtimeConfigPath)
        job = j
        let launchId = makeLaunchId()
        currentLaunchId = launchId
        // 重载期间内核先被回收：旧 revision 不再有效，快照 started 不能再成立。
        activeRev = nil
        replayNeeded = false
        out.append(.runReload(token: j.token, spec: s, launchId: launchId, sessionId: knownSession))
        out.append(.setTimer(TimerKey(.watchdog, subject: j.token), delayMs: config.stepWatchdogMs))
    }

    private func dispatchTeardown() {
        tokens += 1
        let j = Job(kind: .teardown, token: tokens, owner: owner, execToken: nil, specRev: 0, specPath: nil)
        job = j
        stopWatchSerial += 1
        stopSubmitted = true // 从派发起就是「预期中的下线」：随后的 disconnected 不是意外
        out.append(.runTeardown(token: j.token))
        out.append(.setTimer(TimerKey(.watchdog, subject: j.token), delayMs: config.stepWatchdogMs))
        out.append(.setTimer(TimerKey(.stopWatchdog, subject: stopWatchSerial), delayMs: config.stepWatchdogMs))
    }

    /// 放弃当前启动序列：撤掉它的超时（在途任务由 `cancelUselessStartJob` 按意图决定）。
    private func killExec() {
        guard let e = exec else { return }
        exec = nil
        out.append(.cancelTimer(TimerKey(.startTimeout, subject: e.token)))
        log("exec token=\(e.token) (seq=\(e.owner.seq.map(String.init) ?? "nil")) superseded")
    }

    // MARK: - 快照

    private func computeStatus() -> KernelStatus {
        if desired == .on {
            let settled = kernelMatchesIntent() && !reloadRequested && tunnel == .connected
                && exec == nil && job == nil
            return settled ? .started : .starting
        }
        let quiet = tunnel.isDown && !launching && !stopSubmitted && exec == nil && job == nil
        return quiet ? .stopped : .stopping
    }

    private func refreshSnapshot() {
        var candidate = KernelSnapshot(
            epoch: epoch,
            version: snapshot.version,
            status: computeStatus(),
            attempt: attempt,
            desired: desired,
            source: source,
            appliedSeq: appliedSeq,
            activeConfigRevision: activeRev,
            lastFailure: lastFailure,
            selectionsReplayNeeded: replayNeeded,
            retainedConfigPaths: Self.retainedOf(
                storedKnown && !runningRefUnknown,
                [spec?.runtimeConfigPath, storedPath, activePath,
                 job.flatMap { $0.kind == .teardown ? nil : $0.specPath },
                 launching ? pendingActivePath : nil]
                    + unconfirmedStored.map { Optional($0.path) }
            )
        )
        if candidate != snapshot {
            candidate.version = snapshot.version + 1
            snapshot = candidate
        }
    }

    private func log(_ line: String) {
        out.append(.log(line))
    }

    /// 引用集合：去空、去重、排序（顺序稳定，快照相等性不受推导顺序影响）；未知为 nil。
    private static func retainedOf(_ known: Bool, _ paths: [String?]) -> [String]? {
        guard known else { return nil }
        return Array(Set(paths.compactMap { $0 }.filter { !$0.isEmpty })).sorted()
    }

    private func step(_ body: () -> Receipt?) -> CoreStep {
        out.removeAll()
        let receipt = body()
        reconcile()
        refreshSnapshot()
        return CoreStep(effects: out, receipt: receipt)
    }
}
