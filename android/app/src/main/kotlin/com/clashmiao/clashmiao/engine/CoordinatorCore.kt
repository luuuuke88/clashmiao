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
//   · 请求归属（§10.1/§10.2/§10.6）：每个被受理的请求（Dart 的 seq，或一次外部入口）都是一个新的
//     [Owner]，取代上一个。启动序列 [Exec] 与它派发的任务、启动超时都带着**不可变**的归属；
//     只有仍属于当前请求的序列才能把 desired 置 off、写 lastFailure（seq = 该序列服务的 seq）。
//     过时的执行只回收自己留下的资源。配置去重（已就绪且 revision、Service 形态都相同 → 内核无操作）
//     与请求终结分开：新 seq 依然是新请求，按它自己的结果终结。
//   · Service 形态是意图的一部分：请求受理时读取，换形态 = 新请求 = 新序列；收敛判断看
//     **实际运行实例**的类型。
//   · Service 按实例管理（§10.4）：[Inst] 各自记录最大 startId；退休 = 先回收运行时，再对该实例
//     stopSelfResult(其 startId)，**只有**该实例真实的 onDestroy 才算退休完成；换类时旧实例
//     onDestroy 后再起新的。退休超时只报告失败、继续跟踪该实例，绝不越过它去起另一类 Service。
//   · 配置文件引用由原生声明（快照 retainedConfigPaths）：Dart 无从得知原生持久化了哪份 spec，
//     所以每份快照都列出原生之后可能还会读取的全部路径——当前意图的 spec、持久化的 spec
//     （已确认落盘的 + 尚未确认落盘的，见 [onPersistResult]）、运行中内核的 spec、在途启动任务的 spec。
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
    /** 请求 VPN 授权；结果以 [CoordinatorCore.onAuthResult] 回报（token = 启动序列）。 */
    data class RequestAuth(val token: Long) : Effect
    data class CancelAuth(val token: Long) : Effect

    /** 起一个承载内核的 Service；启动成功以 [CoordinatorCore.onServiceStarted] 回报。 */
    data class StartService(val type: ServiceType, val token: Long) : Effect

    /** 对该实例调用 stopSelfResult(maxStartId)；销毁以 [CoordinatorCore.onServiceDestroyed] 回报。 */
    data class RetireService(val inst: Int, val maxStartId: Int) : Effect

    /** 执行层启动任务（token = 任务 token，与启动序列 token 不同）。 */
    data class RunStart(
        val token: Long,
        val inst: Int,
        val spec: LaunchSpec,
        val reload: Boolean,
    ) : Effect

    data class RunTeardown(val token: Long, val inst: Int, val soft: Boolean) : Effect

    /** 置位执行层任务的取消标（任务在当前阻塞调用返回后的检查点看到）。 */
    data class CancelJob(val token: Long) : Effect

    data class SetTimer(val key: TimerKey, val delayMs: Long) : Effect
    data class CancelTimer(val key: TimerKey) : Effect

    /** 持久化当前 desired 与最近一次被受理的 LaunchSpec（计划 P2③）。 */
    data class Persist(val desired: Desired, val spec: LaunchSpec?, val serial: Long = 0L) : Effect

    data class NoticeStarting(val inst: Int, val profileName: String) : Effect
    data class NoticeStarted(val inst: Int, val profileName: String) : Effect
    data class NoticeStopUpdates(val inst: Int) : Effect

    data class Log(val line: String) : Effect
}

/** 一次事件处理的产出：要执行的动作，以及（仅请求事件）回执。 */
class CoreStep(val effects: List<Effect>, val receipt: Receipt? = null)

class CoordinatorCore(
    val epoch: String,
    /** 当前设置的 Service 形态；只在受理开启请求时读取（形态是意图的一部分）。 */
    private val modeProvider: () -> ServiceType,
    private val config: Config = Config(),
    /** 构造时存储里的持久化 spec 路径（外部入口在冷进程里读它）；无持久化 spec 为空。 */
    storedSpecPath: String? = null,
    /** 读取持久化 spec 是否成功；false = 不知道存储里引用了什么，快照的引用集合报「未知」。 */
    storedSpecKnown: Boolean = true,
) {
    data class Config(
        /** 启动超时（含 VPN 授权等待与 Service 拉起），spec §2：30 s。 */
        val startTimeoutMs: Long = 30_000L,
        /** 单个阻塞调用超过该时长判定失联，spec §3：20 s。 */
        val stepWatchdogMs: Long = 20_000L,
        /** 网络切换去抖：同一句柄的抖动合并成一次重载。 */
        val networkDebounceMs: Long = 1_000L,
        /** stopSelfResult 之后等待 onDestroy 的时限；超时只报告，不当作已销毁。 */
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

    /** 请求归属：内部单调 id（外部入口也各有一个）+ Dart 序号（外部入口、旧版转发为空）。 */
    private data class Owner(val id: Long, val seq: Long?)

    private class Inst(val id: Int, val type: ServiceType) {
        var maxStartId = 0
        var rt = Rt.Clean
        var retiring = false
        var retiredAt = 0
        var retireTimedOut = false
        var destroyed = false

        /**
         * 上一次启动以失败告终：runtime 里可能留着半初始化的资源（例如 start() 抛异常的
         * command server）。这样的实例只能完整回收，不能软回收后复用。
         */
        var tainted = false
    }

    /**
     * 一次启动序列：授权 → 拉起 Service → 执行层启动；重载还包含前置回收。
     * [owner] 与 [wantType] 不可变：意图一变就是新请求、新序列。
     */
    private class Exec(val token: Long, val owner: Owner, val wantType: ServiceType) {
        /** 序列第一次真正动手（授权、拉起 Service、派发任务）时才分配 attempt。 */
        var attempt: Long? = null
        var isReload = false
        var authRequested = false
        var authGranted = false

        /** 已对其重新发过 stopSelfResult 的超时退休实例（每个序列只催一次）。 */
        val nudged = HashSet<Int>()
    }

    private enum class JobKind { Start, Teardown }

    private class Job(
        val kind: JobKind,
        val token: Long,
        /** 派发时的当前请求（不可变）。 */
        val owner: Owner,
        /** 派发它的启动序列；与请求无关的回收为空。 */
        val execToken: Long?,
        val inst: Int,
        val soft: Boolean,
        val specRev: Long,
        /** 启动任务读取的运行时配置文件；回收任务为空。 */
        val specPath: String? = null,
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

    /** 已确认在磁盘上的持久化 spec 路径（构造时读取；之后只由成功的 [onPersistResult] 更新）。 */
    private var storedPath: String? = storedSpecPath
    private var storedKnown: Boolean = storedSpecKnown

    /**
     * 已发出、尚未确认落盘的持久化（serial → spec 路径）。失败的也留在这里：内存里已是新值，
     * 之后任何一次整文件写盘都可能把它带到磁盘上；只有更晚的一次确认成功才能清掉它。
     */
    private val unconfirmedStored = LinkedHashMap<Long, String>()
    private var persistSerial = 0L

    /** 运行中内核启动时读取的配置文件路径。 */
    private var activePath: String? = null

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
        retainedConfigPaths = retainedOf(storedSpecKnown, listOf(storedSpecPath)),
    )
        private set

    // 意图
    private var spec: LaunchSpec? = null
    private var wantType = ServiceType.Vpn
    private var owner = Owner(0L, null)
    private var ownerIds = 0L

    /** 已为该请求写过 failure（之后不再用别的失败覆盖它）。 */
    private var failedOwner: Long? = null
    private var reloadRequested = false

    // 事实
    private val insts = LinkedHashMap<Int, Inst>()
    private var job: Job? = null
    private var exec: Exec? = null
    private var kernelUp: Int? = null
    private var tokens = 0L

    /** 已 startForegroundService、尚未到达的 Service 类型（同一时刻至多一个）。 */
    private var pendingBoot: ServiceType? = null
    private var pendingBootToken: Long? = null

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
            claim(Source.App, seq)
            fail(FailureCode.EmptyConfiguration, "missing launch spec", attempt)
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
                claim(src, null)
                fail(FailureCode.EmptyConfiguration, "no launch spec", attempt)
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

    /**
     * 第 [serial] 次持久化的落盘结果（后台线程上 `commit()` 的返回值）。
     *  - 成功：磁盘上就是这一次（及之前）的内容——它成为已确认路径，它和更早的未确认项全部撤下；
     *  - 失败：什么都不撤（旧的已确认路径与新路径都继续声明），只记日志。
     */
    fun onPersistResult(serial: Long, ok: Boolean): CoreStep = step {
        if (!ok) {
            log("persist #$serial not confirmed on disk; keep declaring old and new spec paths")
            return@step null
        }
        // 一次 commit 写出整份内存内容：其中的 spec 是不晚于本次的最后一次写入（可能来自先前
        // 没确认的那次）。
        val path = unconfirmedStored.filterKeys { it <= serial }.values.lastOrNull()
        if (path != null) {
            storedPath = path
            storedKnown = true
        }
        unconfirmedStored.keys.removeAll { it <= serial }
        null
    }

    /** Dart 确认某 attempt 的手选重放完成（幂等；attempt 不是当前值则忽略）。 */
    fun onAckReplay(attempt: Long): CoreStep = step {
        if (attempt == this.attempt) replayNeeded = false
        null
    }

    /** Service.onStartCommand（已先 startForeground）。 */
    fun onServiceStarted(inst: Int, type: ServiceType, startId: Int): CoreStep = step {
        if (pendingBoot == type) {
            pendingBoot = null
            pendingBootToken = null
        }
        val i = insts[inst] ?: Inst(inst, type).also { insts[inst] = it }
        if (i.destroyed) {
            log("ignore start of destroyed instance $inst")
            return@step null
        }
        if (startId > i.maxStartId) i.maxStartId = startId
        if (i.retiring && startId > i.retiredAt) {
            // stopSelfResult 因有更新的 startId 而没有真正停下：实例仍活着，回到普通状态。
            i.retiring = false
            i.retireTimedOut = false
            out += Effect.CancelTimer(TimerKey(TimerKind.Retire, i.id.toLong()))
            log("instance $inst resurrected by startId=$startId")
        }
        null
    }

    /** Service.onDestroy —— 实例退休的唯一事件。 */
    fun onServiceDestroyed(inst: Int): CoreStep = step {
        val i = insts[inst] ?: return@step null
        out += Effect.CancelTimer(TimerKey(TimerKind.Retire, i.id.toLong()))
        val unexpected = !i.retiring
        i.destroyed = true
        if (kernelUp == inst) {
            kernelGone()
            // 已收敛的运行中内核意外退出：属于当前请求。若有启动序列在途，它服务的是新意图，
            // 旧实例的死亡不是它的失败——它照常继续。
            if (unexpected && desired == Desired.On && exec == null) {
                fail(FailureCode.KernelExited, "service destroyed", attempt)
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
        if (e == null || e.token != token || !e.authRequested || e.authGranted) {
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
        if (pendingBootToken == token) {
            pendingBoot = null
            pendingBootToken = null
        }
        val e = exec
        if (e == null || e.token != token) {
            log("service start failure dropped (token=$token)")
            return@step null
        }
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
                    if (!j.soft) inst.tainted = false
                    if (inst.rt == Rt.Clean && inst.destroyed) insts.remove(inst.id)
                }
            }
            JobKind.Start -> {
                // 仍属于当前请求的启动序列；为空 = 过时的执行，只剩回收自身资源的资格。
                val e = exec?.takeIf { it.token == j.execToken }
                when (result) {
                    JobResult.Started -> if (inst != null && !inst.destroyed) {
                        // 内核起来了是事实，不论归属；是否保留由 reconcile 按当前意图决定。
                        kernelUp = j.inst
                        activeRev = j.specRev
                        activePath = j.specPath
                        replayNeeded = true
                        if (kernelMatchesIntent()) {
                            out += Effect.NoticeStarted(j.inst, spec?.profileName.orEmpty())
                        }
                    } else if (e != null) {
                        failExec(e, FailureCode.KernelExited, "service destroyed during start")
                    }
                    is JobResult.Failed -> {
                        inst?.tainted = true
                        if (e != null) failExec(e, result.code, result.message)
                        else log("stale start failure dropped: ${result.code.wire} (owner seq=${j.owner.seq})")
                    }
                    JobResult.Cancelled ->
                        if (e != null) failExec(e, FailureCode.Unknown, "start cancelled unexpectedly")
                    JobResult.TornDown -> log("start job reported TornDown?")
                }
            }
        }
        null
    }

    fun onTimer(key: TimerKey): CoreStep = step {
        when (key.kind) {
            TimerKind.StartTimeout -> {
                val e = exec
                if (e == null || e.token != key.subject) return@step null
                // 30 s 都没到达的 Service 不会再来：别让它挡住后续请求。
                pendingBoot = null
                pendingBootToken = null
                failExec(e, FailureCode.StartTimeout, "start timed out")
            }
            TimerKind.Watchdog -> {
                val j = job
                if (j == null || j.token != key.subject || j.stepSerial != key.serial || j.unresponsive) {
                    return@step null
                }
                j.unresponsive = true
                log("watchdog: step '${j.stepName}' blocked > ${config.stepWatchdogMs}ms (owner seq=${j.owner.seq})")
                val e = exec
                when {
                    // 当前请求是停止：它的完成被卡死的执行层挡住，这是它自己的结果（§3「状态如实保持 stopping」）。
                    desired == Desired.Off -> if (failedOwner != owner.id) {
                        lastFailure = KernelFailure(
                            FailureCode.KernelUnresponsive,
                            "blocked in ${j.stepName}",
                            attempt,
                            owner.seq,
                        )
                        failedOwner = owner.id
                    }
                    // 当前请求自己的序列卡住：它失败。
                    e != null && j.execToken == e.token ->
                        failExec(e, FailureCode.KernelUnresponsive, "blocked in ${j.stepName}")
                    // 过时的执行卡住：不改 desired、不写 failure；当前请求由它自己的 30 s 启动超时兜底。
                    else -> log("stale job unresponsive; request seq=${owner.seq} keeps its own start timeout")
                }
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
                if (!i.retiring || i.destroyed) return@step null
                // 只有真实的 onDestroy 才算退休：继续跟踪该实例，绝不越过它去起另一类 Service。
                i.retireTimedOut = true
                log("retire timeout: instance ${i.id} still alive, keep waiting for onDestroy")
                val e = exec
                if (desired == Desired.On && e != null) {
                    failExec(e, FailureCode.StartService, "previous service instance ${i.id} did not stop")
                }
            }
        }
        null
    }

    // === 意图 ===============================================================

    /** 受理一个新请求：它取代之前的请求。 */
    private fun claim(src: Source, seq: Long?) {
        source = src
        owner = Owner(++ownerIds, seq)
    }

    private fun applyIntent(newDesired: Desired, newSpec: LaunchSpec?, newSource: Source, seq: Long?) {
        claim(newSource, seq)
        // 旧序列不再属于任何当前请求：撤掉它的超时与授权等待；它的在途任务只剩回收自身资源的资格。
        killExec()
        when (newDesired) {
            Desired.Off -> {
                setDesiredOff()
                // 重发 off 且内核仍卡在阻塞调用里：这条新请求同样被挡住，结果如实给它。
                job?.takeIf { it.unresponsive }?.let {
                    lastFailure = KernelFailure(FailureCode.KernelUnresponsive, "blocked in ${it.stepName}", attempt, seq)
                    failedOwner = owner.id
                }
            }
            Desired.On -> {
                val s = requireNotNull(newSpec)
                val changed = desired == Desired.Off || spec != s
                spec = s
                wantType = modeProvider()
                desired = Desired.On
                if (changed) persist()
            }
        }
    }

    private fun setDesiredOff() {
        if (desired == Desired.Off) return
        desired = Desired.Off
        persist()
    }

    private fun persist() {
        val serial = ++persistSerial
        spec?.runtimeConfigPath?.let { unconfirmedStored[serial] = it }
        out += Effect.Persist(desired, spec, serial)
    }

    /** 当前请求失败：写 failure（seq = 当前请求）并把 desired 置 off。 */
    private fun fail(code: FailureCode, message: String, failedAttempt: Long) {
        log("request seq=${owner.seq} failed: ${code.wire} ($message)")
        lastFailure = KernelFailure(code, message, failedAttempt, owner.seq)
        failedOwner = owner.id
        setDesiredOff()
    }

    private fun failExec(e: Exec, code: FailureCode, message: String) {
        if (e !== exec || e.owner != owner || desired != Desired.On) {
            log("stale start failure dropped: ${code.wire} ($message)")
            return
        }
        fail(code, message, e.attempt ?: attempt)
    }

    private fun kernelMatchesIntent(): Boolean {
        val s = spec ?: return false
        val up = kernelUp?.let { insts[it] } ?: return false
        return desired == Desired.On && up.type == wantType && activeRev == s.configRevision
    }

    // === 推导 ===============================================================

    private fun reconcile() {
        cancelUselessStartJob()
        if (desired == Desired.Off) reconcileOff() else reconcileOn()
    }

    /**
     * 在途启动任务若已不能满足当前意图（off、revision 或 Service 形态变了）就打取消标，
     * 让它在当前阻塞调用返回后停手；仍能满足的（同 revision、同形态）继续跑，结果可被新请求沿用。
     */
    private fun cancelUselessStartJob() {
        val j = job ?: return
        if (j.kind != JobKind.Start || j.cancelRequested) return
        val useful = desired == Desired.On &&
            spec?.configRevision == j.specRev &&
            insts[j.inst]?.type == wantType
        if (!useful) {
            j.cancelRequested = true
            out += Effect.CancelJob(j.token)
        }
    }

    private fun reconcileOff() {
        killExec()
        if (job != null) return
        insts.values.firstOrNull { it.rt != Rt.Clean }?.let {
            dispatchTeardown(it, soft = false, e = null)
            return
        }
        retireStrays(keep = null)
    }

    private fun reconcileOn() {
        val s = spec ?: return
        val up = kernelUp?.let { insts[it] }
        if (up != null && kernelMatchesIntent() && !reloadRequested) {
            // 已收敛（含沿用过时执行的成功结果）：当前请求的序列到此完成。
            exec?.let(::completeExec)
            if (job == null) retireStrays(keep = up.id)
            return
        }
        // 没收敛：当前请求必须有自己的序列（及其 30 s 超时），哪怕执行层还被过时任务占着。
        val e = exec ?: newExec().also { exec = it }
        if (job != null) return

        insts.values.firstOrNull { it.destroyed && it.rt != Rt.Clean }?.let {
            dispatchTeardown(it, soft = false, e = e)
            return
        }

        if (up != null) {
            e.isReload = true
            dispatchTeardown(up, soft = up.type == e.wantType, e = e)
            return
        }

        for (inst in insts.values.toList()) {
            if (usable(inst, e)) continue
            if (inst.rt != Rt.Clean) {
                dispatchTeardown(inst, soft = false, e = e)
                return
            }
            if (!inst.retiring && !inst.destroyed) {
                retire(inst)
            } else if (inst.retiring && inst.retireTimedOut && e.nudged.add(inst.id)) {
                retire(inst) // 上一个序列等超时了：新序列再催一次，仍以 onDestroy 为准
            }
        }
        if (insts.values.any { !usable(it, e) }) return // 等旧实例 onDestroy

        val inst = insts.values.firstOrNull { usable(it, e) }
        if (inst == null) {
            requestInstance(e)
            return
        }
        if (inst.rt == Rt.Up) {
            // 上一次启动半途而废留下的资源：被取消的（已完成的步骤都成功）软回收即可复用 command server；
            // 失败的可能留下半初始化资源，必须完整回收，下一次启动重新创建。
            dispatchTeardown(inst, soft = !inst.tainted, e = e)
            return
        }
        if (inst.rt == Rt.Soft && inst.tainted) {
            dispatchTeardown(inst, soft = false, e = e)
            return
        }
        dispatchStart(e, inst, s)
    }

    private fun usable(inst: Inst, e: Exec) =
        inst.type == e.wantType && !inst.retiring && !inst.destroyed

    private fun newExec(): Exec {
        val e = Exec(token = ++tokens, owner = owner, wantType = wantType)
        out += Effect.SetTimer(TimerKey(TimerKind.StartTimeout, e.token), config.startTimeoutMs)
        log("exec token=${e.token} seq=${owner.seq} type=${e.wantType}")
        return e
    }

    private fun ensureAttempt(e: Exec) {
        if (e.attempt != null) return
        attempt++
        e.attempt = attempt
        replayNeeded = false
        log("exec token=${e.token} attempt=$attempt reload=${e.isReload}")
    }

    private fun completeExec(e: Exec) {
        out += Effect.CancelTimer(TimerKey(TimerKind.StartTimeout, e.token))
        exec = null
    }

    private fun requestInstance(e: Exec) {
        // 已请求过的 Service 还没到达：先等它（到达后若类型不对会被退休，再起需要的类型）。
        if (pendingBoot != null) return
        if (e.wantType == ServiceType.Vpn && !e.authGranted) {
            if (!e.authRequested) {
                ensureAttempt(e)
                e.authRequested = true
                out += Effect.RequestAuth(e.token)
            }
            return
        }
        ensureAttempt(e)
        pendingBoot = e.wantType
        pendingBootToken = e.token
        out += Effect.StartService(e.wantType, e.token)
    }

    private fun dispatchStart(e: Exec, inst: Inst, s: LaunchSpec) {
        ensureAttempt(e)
        inst.rt = Rt.Up
        val j = Job(
            JobKind.Start, ++tokens, e.owner, e.token, inst.id,
            soft = false, specRev = s.configRevision, specPath = s.runtimeConfigPath,
        )
        job = j
        out += Effect.NoticeStarting(inst.id, s.profileName)
        out += Effect.RunStart(j.token, inst.id, s, e.isReload)
        out += Effect.SetTimer(TimerKey(TimerKind.Watchdog, j.token, 0L), config.stepWatchdogMs)
    }

    private fun dispatchTeardown(inst: Inst, soft: Boolean, e: Exec?) {
        if (kernelUp == inst.id) {
            kernelGone()
            if (desired == Desired.Off) {
                netBaseline = null
                netPending = null
            }
        }
        e?.let(::ensureAttempt)
        val j = Job(JobKind.Teardown, ++tokens, owner, e?.token, inst.id, soft, specRev = 0L)
        job = j
        out += Effect.NoticeStopUpdates(inst.id)
        out += Effect.RunTeardown(j.token, inst.id, soft)
        out += Effect.SetTimer(TimerKey(TimerKind.Watchdog, j.token, 0L), config.stepWatchdogMs)
    }

    private fun kernelGone() {
        kernelUp = null
        activeRev = null
        activePath = null
        replayNeeded = false
        reloadRequested = false
    }

    private fun retire(inst: Inst) {
        inst.retiring = true
        inst.retiredAt = inst.maxStartId
        inst.retireTimedOut = false
        out += Effect.RetireService(inst.id, inst.maxStartId)
        out += Effect.SetTimer(TimerKey(TimerKind.Retire, inst.id.toLong()), config.retireTimeoutMs)
    }

    /** 除 [keep] 外的实例一律收尾：有残留资源先完整回收，干净的就退休。 */
    private fun retireStrays(keep: Int?) {
        for (inst in insts.values.toList()) {
            if (inst.id == keep) continue
            if (inst.rt != Rt.Clean) {
                if (job == null) dispatchTeardown(inst, soft = false, e = null)
                return
            }
            if (!inst.retiring && !inst.destroyed) retire(inst)
        }
    }

    /** 放弃当前启动序列：撤掉它的超时与授权等待（在途任务由 [cancelUselessStartJob] 按意图决定）。 */
    private fun killExec() {
        val e = exec ?: return
        exec = null
        out += Effect.CancelTimer(TimerKey(TimerKind.StartTimeout, e.token))
        if (e.authRequested && !e.authGranted) out += Effect.CancelAuth(e.token)
        log("exec token=${e.token} (seq=${e.owner.seq}) superseded")
    }

    // === 快照 ===============================================================

    private fun computeStatus(): KernelStatus =
        if (desired == Desired.On) {
            val settled = kernelMatchesIntent() && !reloadRequested && exec == null && job == null
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
            retainedConfigPaths = retainedOf(
                storedKnown,
                listOf(
                    spec?.runtimeConfigPath,
                    storedPath,
                    activePath,
                    job?.takeIf { it.kind == JobKind.Start }?.specPath,
                ) + unconfirmedStored.values,
            ),
        )
        if (candidate != snapshot) snapshot = candidate.copy(version = snapshot.version + 1)
    }

    private fun log(line: String) {
        out += Effect.Log(line)
    }

    private companion object {
        /** 引用集合：去空、去重、排序（顺序稳定，快照相等性不受推导顺序影响）；未知为空。 */
        fun retainedOf(known: Boolean, paths: List<String?>): List<String>? =
            if (!known) null else paths.filterNotNull().filter { it.isNotEmpty() }.distinct().sorted()
    }

    private inline fun step(body: () -> Receipt?): CoreStep {
        out.clear()
        val receipt = body()
        reconcile()
        refreshSnapshot()
        return CoreStep(out.toList(), receipt)
    }
}
