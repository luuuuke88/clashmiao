package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus

// ============================================================================
//  CoordinatorCore —— 连接生命周期协调器的「命令层」状态机（spec §3、§10）。
//
//  纯 Kotlin：输入「事件」（公开的 onXxx 方法），输出「动作」（[Effect] 列表）和新的
//  [KernelSnapshot]。它不碰线程、不碰 Android、不执行任何阻塞调用——主线程上的
//  [KernelCoordinator] 把动作翻译成真正的副作用（起 Service、投递执行层任务、设定时器……），
//  再把结果当作新的事件喂回来。所有时间都是动作（[Effect.SetTimer]）+ 事件（[onTimer]），
//  所以 JVM 单测不需要真实时钟。
//
//  设计要点（对应 spec 条款）：
//   · 单一入口 [reconcile]：每个事件处理完后「按事实重新推导下一步」，每种动作都由标志位保证
//     只发一次（幂等），避免靠「事件序列」推理而漏掉竞态。
//   · 执行层同一时刻至多一个任务（[Job]）；启动链期间收到 off → 立即 stopping，给任务打取消标，
//     任务返回后（无论成败）一律补一次完整回收，含尚未移交的局部实例（§3「停止与阻塞」）。
//   · 执行归属（§10.2）：启动序列 [Exec] 持有 token 与意图代数 gen。只有 token 属于当前序列、
//     且 gen 仍是当前意图时，失败/超时才会把 desired 置 off 并写 lastFailure；否则只回收资源。
//   · Service 按实例管理（§10.4）：[Inst] 各自记录最大 startId；退休 = 先回收运行时，再对该实例
//     stopSelfResult(其 startId)，onDestroy 事件到达才算退休完成；换 Service 类时旧实例 onDestroy 后再起新的。
// ============================================================================

enum class TimerKind { StartTimeout, Watchdog, NetDebounce, Retire }

/**
 * 定时器标识。[slot] 相同的定时器互相替换（同一时刻每个槽只有一个在途）；
 * 触发时整个 key 原样回传 [CoordinatorCore.onTimer]，由核心比对是否仍然有效。
 */
data class TimerKey(val kind: TimerKind, val subject: Long, val serial: Long = 0L) {
    val slot: Pair<TimerKind, Long>
        get() = if (kind == TimerKind.Retire) kind to subject else kind to 0L
}

/** 核心输出的动作，由 [KernelCoordinator] 在主线程按序执行。 */
sealed interface Effect {
    /** 请求 VPN 授权；结果以 [CoordinatorCore.onAuthResult] 回报。 */
    data class RequestAuth(val token: Long) : Effect
    data class CancelAuth(val token: Long) : Effect

    /** 起一个承载内核的 Service；启动成功以 [CoordinatorCore.onServiceStarted] 回报。 */
    data class StartService(val type: ServiceType, val token: Long) : Effect

    /** 对该实例调用 stopSelfResult(maxStartId)；销毁以 [CoordinatorCore.onServiceDestroyed] 回报。 */
    data class RetireService(val inst: Int, val maxStartId: Int) : Effect

    data class RunStart(
        val token: Long,
        val inst: Int,
        val spec: LaunchSpec,
        val reload: Boolean,
    ) : Effect

    data class RunTeardown(val token: Long, val inst: Int, val soft: Boolean) : Effect

    /** 置位执行层任务的取消标（任务在下一个检查点才会看到）。 */
    data class CancelJob(val token: Long) : Effect

    data class SetTimer(val key: TimerKey, val delayMs: Long) : Effect
    data class CancelTimer(val key: TimerKey) : Effect

    /** 持久化当前 desired 与最近一次被受理的 LaunchSpec（计划 P2③）。 */
    data class Persist(val desired: Desired, val spec: LaunchSpec?) : Effect

    data class NoticeStarting(val inst: Int, val profileName: String) : Effect
    data class NoticeStarted(val inst: Int, val profileName: String) : Effect
    data class NoticeStopUpdates(val inst: Int) : Effect

    data class Log(val line: String) : Effect
}

/** 一次事件处理的产出：要执行的动作，以及（仅请求事件）回执。 */
class CoreStep(val effects: List<Effect>, val receipt: Receipt? = null)

class CoordinatorCore(
    val epoch: String,
    /** 当前设置的 Service 形态；只在开始新启动序列或收到请求时读取。 */
    private val modeProvider: () -> ServiceType,
    private val config: Config = Config(),
) {
    data class Config(
        /** 启动超时（含 VPN 授权等待与 Service 拉起），spec §2：30 s。 */
        val startTimeoutMs: Long = 30_000L,
        /** 单个阻塞调用超过该时长判定失联，spec §3：20 s。 */
        val stepWatchdogMs: Long = 20_000L,
        /** 网络切换去抖：同一句柄的抖动合并成一次重载。 */
        val networkDebounceMs: Long = 1_000L,
        /** stopSelfResult 之后等待 onDestroy 的兜底。 */
        val retireTimeoutMs: Long = 10_000L,
    )

    // === 内部类型 ===========================================================

    private enum class Rt {
        /** 运行时未持有任何资源。 */
        Clean,

        /** 内核在运行，或启动做到一半（持有 tun / libbox service / command server 等）。 */
        Up,

        /** 仅回收了 tun / libbox service，command server 仍保留（重载用）。 */
        Soft,
    }

    private class Inst(val id: Int, val type: ServiceType) {
        var maxStartId = 0
        var rt = Rt.Clean
        var retiring = false
        var retiredAt = 0
        var destroyed = false
    }

    /** 一次启动序列：授权 → 拉起 Service → 执行层启动；重载还包含前置回收。 */
    private class Exec(
        val token: Long,
        var gen: Long,
        val attempt: Long,
        val wantType: ServiceType,
        val isReload: Boolean,
    ) {
        var authRequested = false
        var authGranted = false
        var bootRequested = false
        var jobDispatched = false
        var dead = false
    }

    private enum class JobKind { Start, Teardown }

    private class Job(
        val kind: JobKind,
        val token: Long,
        val inst: Int,
        val soft: Boolean,
        val specRev: Long,
    ) {
        var cancelRequested = false
        var stepSerial = 0L
        var stepName = ""
        var unresponsive = false
    }

    // === 状态 ===============================================================

    // 快照字段
    private var attempt = 0L
    private var desired = Desired.Off
    private var source = Source.System
    private var appliedSeq = 0L
    private var activeRev: Long? = null
    private var lastFailure: KernelFailure? = null
    private var replayNeeded = false

    var snapshot: KernelSnapshot = KernelSnapshot(
        epoch = epoch,
        version = 1L,
        status = KernelStatus.Stopped,
        attempt = 0L,
        desired = Desired.Off,
        source = Source.System,
        appliedSeq = 0L,
        activeConfigRevision = null,
        lastFailure = null,
        selectionsReplayNeeded = false,
    )
        private set

    // 意图
    private var spec: LaunchSpec? = null

    /** 意图代数：desired 翻转、开启时 revision 变化、失败置 off 时 +1。 */
    private var gen = 0L

    /** 当前 desired 对应的 Dart 请求序号；外部入口设定时为空。 */
    private var desiredSeq: Long? = null
    private var reloadRequested = false

    // 事实
    private val insts = LinkedHashMap<Int, Inst>()
    private var job: Job? = null
    private var exec: Exec? = null
    private var kernelUp: Int? = null
    private var tokens = 0L

    // 网络
    private var netBaseline: Long? = null
    private var netPending: Long? = null
    private var netSerial = 0L

    private val out = ArrayList<Effect>()

    /** 核心是否仍在跟踪该实例（协调器据此释放不再需要的句柄）。 */
    fun knows(inst: Int): Boolean = insts.containsKey(inst)

    // === 事件入口 ===========================================================

    /**
     * Dart 的带序号请求（spec §10.1）。[epoch]/[seq] 为空 = 旧版 Pigeon start/stop/restart 转发，
     * 不参与序号校验也不推进 appliedSeq。
     */
    fun onRequest(
        epoch: String?,
        seq: Long?,
        desired: Desired,
        launch: LaunchSpec?,
        reason: String = "",
    ): CoreStep = step {
        if (epoch != null && epoch != this.epoch) {
            log("request seq=$seq rejected: wrongEpoch (got=${epoch.take(8)})")
            return@step Receipt(false, RejectReason.WrongEpoch, this.epoch, appliedSeq)
        }
        if (seq != null && seq <= appliedSeq) {
            // 过期请求：不改变任何状态；Off 的重发不在此列（seq 更新才会进来）。
            log("request seq=$seq rejected: stale (appliedSeq=$appliedSeq)")
            return@step Receipt(false, RejectReason.Stale, this.epoch, appliedSeq)
        }
        if (seq != null) appliedSeq = seq
        log("request seq=$seq desired=${desired.wire} reason=$reason")
        val effectiveLaunch = launch ?: spec
        if (desired == Desired.On && effectiveLaunch == null) {
            // 协议约定 on 必带 LaunchSpec（桥层已校验）；万一缺失且没有可沿用的 spec，按空配置失败。
            source = Source.App
            desiredSeq = seq
            lastFailure = KernelFailure(FailureCode.EmptyConfiguration, "missing launch spec", attempt, seq)
            setDesiredOff()
        } else {
            applyIntent(desired, effectiveLaunch, Source.App, seq)
        }
        Receipt(true, null, this.epoch, appliedSeq)
    }

    /**
     * 外部入口（磁贴、快捷方式、开机、通知栏停止、系统撤销）。
     * on 时用 [fallbackSpec]（持久化的最近 LaunchSpec）补足没有内存 spec 的冷进程。
     */
    fun onExternal(src: Source, desired: Desired, fallbackSpec: LaunchSpec?): CoreStep = step {
        log("external source=${src.wire} desired=${desired.wire}")
        if (desired == Desired.On) {
            val s = spec ?: fallbackSpec
            if (s == null) {
                source = src
                desiredSeq = null
                lastFailure = KernelFailure(FailureCode.EmptyConfiguration, "no launch spec", attempt, null)
                return@step null
            }
            applyIntent(Desired.On, s, src, null)
        } else {
            applyIntent(Desired.Off, null, src, null)
        }
        null
    }

    /** libbox 的 serviceReload / setSystemProxyEnabled 回调与旧 RELOAD 广播（source 由调用方给出）。 */
    fun onReloadRequested(src: Source): CoreStep = step {
        if (desired == Desired.On && spec != null && exec == null && kernelUp != null) {
            log("reload requested by ${src.wire}")
            source = src
            reloadRequested = true
        } else {
            log("reload request ignored (desired=${desired.wire}, starting=${exec != null})")
        }
        null
    }

    /** 默认网络句柄变化（NetworkWatcher）。按句柄去重、吸收初始事件，去抖后重载。 */
    fun onNetworkResolved(handle: Long): CoreStep = step {
        val settled = desired == Desired.On && spec != null && kernelUp != null && exec == null && job == null
        when {
            !settled -> {
                // 启动中 / 未运行：只记基线（arm 之后系统会立刻补发一次当前网络）。
                netBaseline = handle
                netPending = null
            }
            netBaseline == null -> netBaseline = handle
            handle == netBaseline -> netPending = null
            else -> {
                netPending = handle
                netSerial++
                out += Effect.SetTimer(TimerKey(TimerKind.NetDebounce, 0L, netSerial), config.networkDebounceMs)
            }
        }
        null
    }

    /** Dart 确认某 attempt 的手选重放完成（幂等；attempt 不是当前值则忽略）。 */
    fun onAckReplay(attempt: Long): CoreStep = step {
        if (attempt == this.attempt) replayNeeded = false
        null
    }

    /** Service.onStartCommand（已先 startForeground）。 */
    fun onServiceStarted(inst: Int, type: ServiceType, startId: Int): CoreStep = step {
        val existing = insts[inst]
        val i = existing ?: Inst(inst, type).also { insts[inst] = it }
        if (i.destroyed) {
            log("ignore start of destroyed instance $inst")
            return@step null
        }
        if (startId > i.maxStartId) i.maxStartId = startId
        if (i.retiring && startId > i.retiredAt) {
            // stopSelfResult 因有更新的 startId 而没有真正停下：实例仍活着，回到普通状态。
            i.retiring = false
            out += Effect.CancelTimer(TimerKey(TimerKind.Retire, i.id.toLong()))
            log("instance $inst resurrected by startId=$startId")
        }
        exec?.let { if (!it.dead) it.bootRequested = false }
        null
    }

    /** Service.onDestroy。 */
    fun onServiceDestroyed(inst: Int): CoreStep = step {
        val i = insts[inst] ?: return@step null
        out += Effect.CancelTimer(TimerKey(TimerKind.Retire, i.id.toLong()))
        if (i.retiring) {
            i.destroyed = true
        } else {
            // 非预期销毁（系统回收等）：运行时仍可能持有资源，补回收；内核在跑则视为退出。
            i.destroyed = true
            if (kernelUp == inst) {
                kernelUp = null
                activeRev = null
                replayNeeded = false
                if (desired == Desired.On) {
                    lastFailure = KernelFailure(FailureCode.KernelExited, "service destroyed", attempt, desiredSeq)
                    setDesiredOff()
                }
            }
        }
        if (i.rt == Rt.Clean && job?.inst != inst) insts.remove(inst)
        null
    }

    /** VpnService.onRevoke（系统或其他 VPN 撤销）。 */
    fun onServiceRevoked(inst: Int): CoreStep = step {
        val i = insts[inst]
        if (i == null || i.retiring || i.destroyed) return@step null
        log("service $inst revoked")
        if (desired == Desired.On) applyIntent(Desired.Off, null, Source.System, null)
        else source = Source.System
        null
    }

    /** VPN 授权结果。token 不属于当前启动序列则丢弃（spec §3、§10.2）。 */
    fun onAuthResult(token: Long, granted: Boolean, message: String = ""): CoreStep = step {
        val e = exec
        if (e == null || e.dead || e.token != token || !e.authRequested || e.authGranted) {
            log("auth result dropped (token=$token granted=$granted)")
            return@step null
        }
        if (granted) {
            e.authGranted = true
        } else {
            failExec(e, FailureCode.PermissionDenied, message.ifEmpty { "vpn permission denied" })
        }
        null
    }

    /** startForegroundService 本身抛了异常。 */
    fun onServiceStartFailed(token: Long, message: String): CoreStep = step {
        val e = exec
        if (e == null || e.dead || e.token != token) {
            log("service start failure dropped (token=$token)")
            return@step null
        }
        e.bootRequested = false
        failExec(e, FailureCode.StartService, message)
        null
    }

    /** 执行层任务进入一个新的阻塞步骤（重新计 20 s 看门狗）。 */
    fun onJobStep(token: Long, name: String): CoreStep = step {
        val j = job
        if (j == null || j.token != token) return@step null
        j.stepSerial++
        j.stepName = name
        j.unresponsive = false
        out += Effect.SetTimer(TimerKey(TimerKind.Watchdog, token, j.stepSerial), config.stepWatchdogMs)
        null
    }

    fun onJobFinished(token: Long, result: JobResult): CoreStep = step {
        val j = job
        if (j == null || j.token != token) {
            log("job result dropped (token=$token result=$result)")
            return@step null
        }
        job = null
        out += Effect.CancelTimer(TimerKey(TimerKind.Watchdog, token))
        val inst = insts[j.inst]
        when (j.kind) {
            JobKind.Teardown -> {
                if (inst != null) {
                    inst.rt = if (j.soft) Rt.Soft else Rt.Clean
                    if (inst.rt == Rt.Clean && inst.destroyed) insts.remove(inst.id)
                }
            }
            JobKind.Start -> {
                val e = exec?.takeIf { it.token == token }
                if (e != null) out += Effect.CancelTimer(TimerKey(TimerKind.StartTimeout, token))
                when (result) {
                    JobResult.Started -> {
                        if (e != null && !e.dead && inst != null && !inst.destroyed) {
                            kernelUp = j.inst
                            activeRev = j.specRev
                            replayNeeded = true
                            out += Effect.NoticeStarted(j.inst, spec?.profileName.orEmpty())
                        } else if (e != null && !e.dead) {
                            failExec(e, FailureCode.KernelExited, "service destroyed during start")
                        }
                        // 序列已被放弃：内核其实起来了，rt 仍是 Up，下面的 reconcile 会补完整回收。
                    }
                    is JobResult.Failed -> if (e != null && !e.dead) failExec(e, result.code, result.message)
                    JobResult.Cancelled ->
                        if (e != null && !e.dead) failExec(e, FailureCode.Unknown, "start cancelled unexpectedly")
                    JobResult.TornDown -> log("start job reported TornDown?")
                }
                if (e != null) exec = null
            }
        }
        null
    }

    fun onTimer(key: TimerKey): CoreStep = step {
        when (key.kind) {
            TimerKind.StartTimeout -> {
                val e = exec
                if (e == null || e.dead || e.token != key.subject) return@step null
                if (e.gen == gen && desired == Desired.On) {
                    failExec(e, FailureCode.StartTimeout, "start timed out")
                } else {
                    // 意图已变、该序列早已过时：放弃它，新意图会开新序列。
                    killExec()
                }
            }
            TimerKind.Watchdog -> {
                val j = job
                if (j == null || j.token != key.subject || j.stepSerial != key.serial || j.unresponsive) {
                    return@step null
                }
                j.unresponsive = true
                log("watchdog: step '${j.stepName}' blocked > ${config.stepWatchdogMs}ms")
                if (desired == Desired.On) setDesiredOff()
                lastFailure = KernelFailure(
                    FailureCode.KernelUnresponsive,
                    "blocked in ${j.stepName}",
                    attempt,
                    desiredSeq,
                )
            }
            TimerKind.NetDebounce -> {
                if (key.serial != netSerial) return@step null
                val pending = netPending
                netPending = null
                if (pending != null && pending != netBaseline &&
                    desired == Desired.On && spec != null && kernelUp != null && exec == null && job == null
                ) {
                    log("network changed -> reload")
                    netBaseline = pending
                    reloadRequested = true
                }
            }
            TimerKind.Retire -> {
                val i = insts[key.subject.toInt()] ?: return@step null
                if (i.retiring && !i.destroyed) {
                    log("retire timeout: instance ${i.id} treated as destroyed")
                    i.destroyed = true
                    if (i.rt == Rt.Clean && job?.inst != i.id) insts.remove(i.id)
                }
            }
        }
        null
    }

    // === 意图 ===============================================================

    private fun applyIntent(newDesired: Desired, newSpec: LaunchSpec?, newSource: Source, seq: Long?) {
        source = newSource
        desiredSeq = seq
        when (newDesired) {
            Desired.Off -> {
                if (desired == Desired.On) setDesiredOff()
                // 重发 off 且内核仍卡在阻塞调用里：失败归属改到这条新请求，Dart 的重发才有结果可等。
                val f = lastFailure
                if (f != null && f.code == FailureCode.KernelUnresponsive && job?.unresponsive == true) {
                    lastFailure = f.copy(seq = seq)
                }
            }
            Desired.On -> {
                val s = requireNotNull(newSpec)
                val revChanged = spec?.configRevision != s.configRevision
                val specChanged = spec != s
                spec = s
                var changed = specChanged
                if (desired == Desired.Off) {
                    desired = Desired.On
                    gen++
                    changed = true
                } else if (revChanged) {
                    gen++
                }
                // 尚未交给执行层的序列直接跟随新意图；已在阻塞调用里的序列保持原 gen（变成过时）。
                exec?.let { if (!it.dead && !it.jobDispatched) it.gen = gen }
                val up = kernelUp?.let { insts[it] }
                if (up != null && modeProvider() != up.type) reloadRequested = true
                if (changed) persist()
            }
        }
    }

    private fun setDesiredOff() {
        if (desired == Desired.Off) return
        desired = Desired.Off
        gen++
        persist()
    }

    private fun persist() {
        out += Effect.Persist(desired, spec)
    }

    private fun failExec(e: Exec, code: FailureCode, message: String) {
        if (e.gen == gen && desired == Desired.On) {
            log("start failed: ${code.wire} ($message)")
            lastFailure = KernelFailure(code, message, e.attempt, desiredSeq)
            setDesiredOff()
        } else {
            log("stale start failure dropped: ${code.wire} ($message)")
        }
    }

    // === 推导 ===============================================================

    private fun reconcile() {
        if (desired == Desired.Off) reconcileOff() else reconcileOn()
    }

    private fun reconcileOff() {
        killExec()
        if (job != null) return
        insts.values.firstOrNull { it.rt != Rt.Clean }?.let {
            dispatchTeardown(it, soft = false)
            return
        }
        retireStrays(keep = null)
    }

    private fun reconcileOn() {
        val s = spec ?: return
        if (job != null) return
        exec?.let { if (it.dead) exec = null }

        insts.values.firstOrNull { it.destroyed && it.rt != Rt.Clean }?.let {
            dispatchTeardown(it, soft = false)
            return
        }

        val up = kernelUp?.let { insts[it] }
        val needReload = up != null && (reloadRequested || activeRev != s.configRevision)
        if (exec == null) {
            if (up != null && !needReload) {
                retireStrays(keep = up.id)
                return
            }
            exec = newExec(isReload = up != null)
        }
        val e = requireNotNull(exec)

        if (up != null) {
            dispatchTeardown(up, soft = up.type == e.wantType)
            return
        }

        for (inst in insts.values.toList()) {
            if (usable(inst, e)) continue
            if (inst.rt != Rt.Clean) {
                dispatchTeardown(inst, soft = false)
                return
            }
            if (!inst.retiring && !inst.destroyed) retire(inst)
        }
        if (insts.values.any { !usable(it, e) }) return // 等旧实例 onDestroy

        val inst = insts.values.firstOrNull { usable(it, e) }
        if (inst == null) {
            requestInstance(e)
            return
        }
        if (inst.rt == Rt.Up) {
            // 上一次启动半途而废留下的资源：先软回收再启动。
            dispatchTeardown(inst, soft = true)
            return
        }
        dispatchStart(e, inst, s)
    }

    private fun usable(inst: Inst, e: Exec) =
        inst.type == e.wantType && !inst.retiring && !inst.destroyed

    private fun newExec(isReload: Boolean): Exec {
        attempt++
        replayNeeded = false
        reloadRequested = false
        val e = Exec(
            token = ++tokens,
            gen = gen,
            attempt = attempt,
            wantType = modeProvider(),
            isReload = isReload,
        )
        out += Effect.SetTimer(TimerKey(TimerKind.StartTimeout, e.token), config.startTimeoutMs)
        log("exec token=${e.token} attempt=$attempt type=${e.wantType} reload=$isReload")
        return e
    }

    private fun requestInstance(e: Exec) {
        if (e.bootRequested) return
        if (e.wantType == ServiceType.Vpn && !e.authGranted) {
            if (!e.authRequested) {
                e.authRequested = true
                out += Effect.RequestAuth(e.token)
            }
            return
        }
        e.bootRequested = true
        out += Effect.StartService(e.wantType, e.token)
    }

    private fun dispatchStart(e: Exec, inst: Inst, s: LaunchSpec) {
        inst.rt = Rt.Up
        e.jobDispatched = true
        job = Job(JobKind.Start, e.token, inst.id, soft = false, specRev = s.configRevision)
        out += Effect.NoticeStarting(inst.id, s.profileName)
        out += Effect.RunStart(e.token, inst.id, s, e.isReload)
        out += Effect.SetTimer(TimerKey(TimerKind.Watchdog, e.token, 0L), config.stepWatchdogMs)
    }

    private fun dispatchTeardown(inst: Inst, soft: Boolean) {
        if (kernelUp == inst.id) {
            kernelUp = null
            activeRev = null
            replayNeeded = false
            if (desired == Desired.Off) {
                netBaseline = null
                netPending = null
            }
        }
        val token = ++tokens
        job = Job(JobKind.Teardown, token, inst.id, soft, specRev = 0L)
        out += Effect.NoticeStopUpdates(inst.id)
        out += Effect.RunTeardown(token, inst.id, soft)
        out += Effect.SetTimer(TimerKey(TimerKind.Watchdog, token, 0L), config.stepWatchdogMs)
    }

    private fun retire(inst: Inst) {
        inst.retiring = true
        inst.retiredAt = inst.maxStartId
        out += Effect.RetireService(inst.id, inst.maxStartId)
        out += Effect.SetTimer(TimerKey(TimerKind.Retire, inst.id.toLong()), config.retireTimeoutMs)
    }

    /** 除 [keep] 外的实例一律收尾：有残留资源先完整回收，干净的就退休。 */
    private fun retireStrays(keep: Int?) {
        for (inst in insts.values.toList()) {
            if (inst.id == keep) continue
            if (inst.rt != Rt.Clean) {
                if (job == null) dispatchTeardown(inst, soft = false)
                return
            }
            if (!inst.retiring && !inst.destroyed) retire(inst)
        }
    }

    /** 放弃当前启动序列：打取消标；若执行层空闲则序列立即结束。 */
    private fun killExec() {
        val e = exec ?: return
        if (!e.dead) {
            e.dead = true
            out += Effect.CancelTimer(TimerKey(TimerKind.StartTimeout, e.token))
            if (e.authRequested && !e.authGranted) out += Effect.CancelAuth(e.token)
            val j = job
            if (j != null && j.kind == JobKind.Start && j.token == e.token && !j.cancelRequested) {
                j.cancelRequested = true
                out += Effect.CancelJob(j.token)
            }
        }
        if (job == null) exec = null
    }

    // === 快照 ===============================================================

    private fun computeStatus(): KernelStatus =
        if (desired == Desired.On) {
            val settled = kernelUp != null && exec == null && job == null &&
                !reloadRequested && activeRev == spec?.configRevision
            if (settled) KernelStatus.Started else KernelStatus.Starting
        } else {
            val quiet = kernelUp == null && exec == null && job == null &&
                insts.values.all { it.rt == Rt.Clean }
            if (quiet) KernelStatus.Stopped else KernelStatus.Stopping
        }

    private fun refreshSnapshot() {
        val candidate = KernelSnapshot(
            epoch = epoch,
            version = snapshot.version,
            status = computeStatus(),
            attempt = attempt,
            desired = desired,
            source = source,
            appliedSeq = appliedSeq,
            activeConfigRevision = activeRev,
            lastFailure = lastFailure,
            selectionsReplayNeeded = replayNeeded,
        )
        if (candidate != snapshot) snapshot = candidate.copy(version = snapshot.version + 1)
    }

    private fun log(line: String) {
        out += Effect.Log(line)
    }

    private inline fun step(body: () -> Receipt?): CoreStep {
        out.clear()
        val receipt = body()
        reconcile()
        refreshSnapshot()
        return CoreStep(out.toList(), receipt)
    }
}
