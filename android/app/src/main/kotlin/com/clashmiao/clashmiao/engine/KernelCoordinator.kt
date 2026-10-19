package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import java.util.concurrent.atomic.AtomicInteger

/**
 * 承载内核的 Service 实例对协调器暴露的句柄（由 [KernelHost] 实现）。
 */
interface ServiceHandle {
    /** 协调器分配的实例 id（进程内单调）。 */
    val id: Int
    val type: ServiceType
    val kernelRuntime: KernelRuntime

    /** 对**该实例**调用 stopSelfResult(startId)；返回 false = 有更新的 startId 尚未处理。 */
    fun stopSelfResult(startId: Int): Boolean

    fun noticeStarting(profileName: String)
    fun noticeStarted(profileName: String)
    fun noticeStopUpdates()
}

/** 手选出站的实际写入（生产实现：libbox 独立命令客户端，经当前 command server 写入运行中的内核）。 */
fun interface OutboundSelector {
    fun select(group: String, outbound: String)
}

/** [KernelCoordinator.selectOutbound] 的结果。 */
sealed interface SelectResult {
    data object Ok : SelectResult

    /** 期望的 attempt 已不是正在运行的内核实例：没有写入任何东西（spec §10.7）。 */
    data class Stale(val message: String) : SelectResult
    data class Failed(val message: String) : SelectResult
}

/** [KernelCoordinator] 需要平台提供的能力；Android 实现见 [AndroidCoordinatorPlatform]。 */
interface CoordinatorPlatform {
    fun isMainThread(): Boolean
    fun post(r: Runnable)

    /** 同一 slot 的定时器互相替换。 */
    fun schedule(slot: Any, delayMs: Long, r: Runnable)
    fun cancel(slot: Any)

    /** 请求 VPN 授权；结果经 [KernelCoordinator.onAuthResult] 回报。 */
    fun requestVpnAuth(token: Long)
    fun cancelVpnAuth(token: Long)

    /** 拉起承载内核的 Service；可能抛异常（后台启动限制等）。 */
    fun startService(type: ServiceType)

    fun currentMode(): ServiceType
    fun log(line: String)
}

/**
 * 进程级连接协调器（spec §3）：**命令层**。
 *
 * 所有状态变化都发生在主线程、同步完成、永不阻塞：
 *   事件 → [CoordinatorCore]（纯状态机）→ 动作 → 本类在主线程执行
 *   （起 Service、投递 [KernelExecutor] 任务、设定时器、持久化、通知……）→ 结果当作新事件再喂回核心。
 *
 * 动作执行过程中产生的事件（例如授权立即通过）排队，等当前动作列表执行完再处理，
 * 所以核心永远不会被重入。
 */
class KernelCoordinator(
    private val platform: CoordinatorPlatform,
    private val executor: KernelExecutor,
    private val store: KernelStore,
    val logs: LogBuffer,
    epoch: String,
    config: CoordinatorCore.Config = CoordinatorCore.Config(),
    private val selector: OutboundSelector = OutboundSelector { _, _ -> error("no outbound selector") },
) {
    private val core: CoordinatorCore = readStoredSpecPath().let { (path, known) ->
        CoordinatorCore(epoch, platform::currentMode, config, storedSpecPath = path, storedSpecKnown = known)
    }

    /**
     * 选择栅栏：已就绪（started）的内核实例的 attempt，否则为空。主线程在**执行任何动作之前**
     * 更新它——所以派发回收 / 重载任务之前它已经清空；执行层线程上的选择任务据此复查。
     */
    @Volatile private var liveAttempt: Long? = null

    private val handles = HashMap<Int, ServiceHandle>()
    private val instanceIds = AtomicInteger(0)

    private val snapshotListeners = ArrayList<(KernelSnapshot) -> Unit>()
    private val alertListeners = ArrayList<(AlertCode, String?) -> Unit>()
    private var published: KernelSnapshot? = null

    private val queue = ArrayDeque<() -> CoreStep>()
    private var draining = false

    // === 查询 ===============================================================

    /** 当前权威快照（主线程）。 */
    val snapshot: KernelSnapshot get() = core.snapshot

    fun nextInstanceId(): Int = instanceIds.incrementAndGet()

    /** 订阅快照变化（主线程回调）。订阅时立即推送当前值。返回取消函数。 */
    fun observeSnapshot(listener: (KernelSnapshot) -> Unit): () -> Unit {
        snapshotListeners += listener
        listener(core.snapshot)
        return { snapshotListeners -= listener }
    }

    fun observeAlerts(listener: (AlertCode, String?) -> Unit): () -> Unit {
        alertListeners += listener
        return { alertListeners -= listener }
    }

    /** 非生命周期的提示（例如通知权限被拒）。 */
    fun emitAlert(code: AlertCode, message: String?) = onMain {
        alertListeners.toList().forEach { it(code, message) }
    }

    // === Dart 请求 ==========================================================

    /**
     * Dart 的带序号请求。必须在主线程调用（Pigeon 回调线程）；回执同步返回，只表示入队/被拒绝。
     */
    fun request(
        epoch: String?,
        seq: Long?,
        desired: Desired,
        launch: LaunchSpec?,
        reason: String = "",
    ): Receipt {
        check(platform.isMainThread()) { "request() must be called on the main thread" }
        var receipt: Receipt? = null
        dispatch {
            core.onRequest(epoch, seq, desired, launch, reason).also { receipt = it.receipt }
        }
        // 若恰好处于动作执行中（不应发生），请求已排队，回执此刻未知：按「已入队」答复。
        return receipt ?: Receipt(true, null, core.epoch, core.snapshot.appliedSeq)
    }

    fun acknowledgeReplay(attempt: Long) = onMain { dispatch { core.onAckReplay(attempt) } }

    /**
     * 手选出站（spec §10.7）。[expectedAttempt] 非空时，校验与写入都绑定到该 attempt 的内核实例：
     *  1. 主线程：该 attempt 必须是当前已就绪的实例，否则立即 stale；
     *  2. 写入在执行层线程上与生命周期任务串行执行，执行前再按栅栏复查——期间主线程若已为该实例
     *     派发回收 / 重载，栅栏已清空，返回 stale 且不写入；否则写入只会落到该实例
     *     （它的回收任务排在这次写入之后）。新实例永远不会收到旧 attempt 的写入。
     * [done] 在主线程回调，恰好一次。必须在主线程调用。
     */
    fun selectOutbound(
        group: String,
        outbound: String,
        expectedAttempt: Long?,
        done: (SelectResult) -> Unit,
    ) {
        check(platform.isMainThread()) { "selectOutbound() must be called on the main thread" }
        if (expectedAttempt != null && liveAttempt != expectedAttempt) {
            done(SelectResult.Stale(staleSelection(expectedAttempt)))
            return
        }
        executor.runSerialized {
            val result = if (expectedAttempt != null && liveAttempt != expectedAttempt) {
                SelectResult.Stale(staleSelection(expectedAttempt))
            } else {
                try {
                    selector.select(group, outbound)
                    SelectResult.Ok
                } catch (t: Throwable) {
                    SelectResult.Failed(t.message ?: t.toString())
                }
            }
            platform.post(Runnable { done(result) })
        }
    }

    private fun staleSelection(expected: Long) =
        "attempt $expected is not the running instance (live=${liveAttempt ?: "none"})"

    // === 外部入口 ===========================================================

    /** 磁贴 / 快捷方式 / 开机 / 通知栏等外部入口。on 时使用持久化的最近 LaunchSpec。 */
    fun external(source: Source, desired: Desired) = onMain {
        val fallback = if (desired == Desired.On) store.loadSpec() else null
        dispatch { core.onExternal(source, desired, fallback) }
    }

    /** 磁贴/快捷方式的「切换」：按 desired 翻转（过渡期也能停）。 */
    fun toggleExternal(source: Source) = onMain {
        val next = if (core.snapshot.desired == Desired.On) Desired.Off else Desired.On
        external(source, next)
    }

    /** 开机/升级后按持久化的 desired 恢复。 */
    fun resumeFromBoot() = onMain {
        if (store.loadDesired() == Desired.On) external(Source.Boot, Desired.On)
    }

    fun onReloadRequested(source: Source) = onMain { dispatch { core.onReloadRequested(source) } }

    fun onNetworkResolved(handle: Long) = onMain { dispatch { core.onNetworkResolved(handle) } }

    // === Service / 授权事件 =================================================

    fun onServiceStarted(handle: ServiceHandle, startId: Int) = onMain {
        handles[handle.id] = handle
        dispatch { core.onServiceStarted(handle.id, handle.type, startId) }
    }

    fun onServiceDestroyed(handle: ServiceHandle) = onMain {
        handles[handle.id] = handle // 兜底：销毁时回收可能仍需要它
        dispatch { core.onServiceDestroyed(handle.id) }
    }

    fun onServiceRevoked(handle: ServiceHandle) = onMain {
        dispatch { core.onServiceRevoked(handle.id) }
    }

    fun onAuthResult(token: Long, granted: Boolean, message: String = "") = onMain {
        dispatch { core.onAuthResult(token, granted, message) }
    }

    // === 遗留入口（旧 Dart 控制器经旧 Pigeon start/stop/restart 调用，计划 P2④）========

    /** 旧 start：意图已经是开启时是空操作（旧实现里重复 start 在非 Stopped 时同样被忽略），否则按给定配置开启。 */
    fun legacyStart(launch: LaunchSpec) = onMain {
        if (core.snapshot.desired == Desired.On) return@onMain
        dispatch { core.onRequest(null, null, Desired.On, launch, "legacyStart") }
    }

    fun legacyStop() = onMain {
        dispatch { core.onRequest(null, null, Desired.Off, null, "legacyStop") }
    }

    /** 旧 restart：仅当当前意图是开启时才有意义；用全新 revision 强制重载。 */
    fun legacyRestart(launch: LaunchSpec) = onMain {
        if (core.snapshot.desired != Desired.On) return@onMain
        dispatch { core.onRequest(null, null, Desired.On, launch, "legacyRestart") }
    }

    // === 内部：派发与动作执行 ================================================

    private fun onMain(block: () -> Unit) {
        if (platform.isMainThread()) block() else platform.post(Runnable { block() })
    }

    private fun dispatch(supplier: () -> CoreStep) {
        queue.addLast(supplier)
        if (draining) return
        draining = true
        try {
            while (queue.isNotEmpty()) {
                val step = queue.removeFirst()()
                // 先更新选择栅栏，再执行动作（其中可能派发回收 / 重载任务）。
                liveAttempt = core.snapshot.let { if (it.status == KernelStatus.Started) it.attempt else null }
                execute(step.effects)
                publishIfChanged()
                pruneHandles()
            }
        } finally {
            draining = false
        }
    }

    private fun publishIfChanged() {
        val s = core.snapshot
        if (s === published) return
        published = s
        platform.log("snapshot ${s.logLine()}")
        snapshotListeners.toList().forEach { it(s) }
    }

    private fun pruneHandles() {
        handles.keys.retainAll { core.knows(it) }
    }

    private fun execute(effects: List<Effect>) {
        for (e in effects) {
            when (e) {
                is Effect.Log -> platform.log("core: ${e.line}")

                is Effect.RequestAuth -> platform.requestVpnAuth(e.token)
                is Effect.CancelAuth -> platform.cancelVpnAuth(e.token)

                is Effect.StartService -> try {
                    platform.startService(e.type)
                } catch (t: Throwable) {
                    val token = e.token
                    val message = t.message ?: t.toString()
                    queue.addLast { core.onServiceStartFailed(token, message) }
                }

                is Effect.RetireService -> {
                    val h = handles[e.inst]
                    if (h == null) {
                        // 不伪造 onDestroy：退休只以该实例真实的 onDestroy 为准，超时由核心如实报告。
                        platform.log("retire instance ${e.inst}: no handle, waiting for onDestroy")
                    } else {
                        val stopped = try {
                            h.stopSelfResult(e.maxStartId)
                        } catch (t: Throwable) {
                            platform.log("stopSelfResult failed: $t")
                            true
                        }
                        platform.log("retire instance ${e.inst} startId=${e.maxStartId} stopped=$stopped")
                    }
                }

                is Effect.RunStart -> {
                    val h = handles[e.inst]
                    if (h == null) {
                        val token = e.token
                        queue.addLast {
                            core.onJobFinished(token, JobResult.Failed(FailureCode.StartService, "service gone"))
                        }
                    } else {
                        executor.submitStart(e.token, h.kernelRuntime, e.spec, e.reload, ::onJobStep, ::onJobDone)
                    }
                }

                is Effect.RunTeardown -> {
                    val h = handles[e.inst]
                    if (h == null) {
                        val token = e.token
                        queue.addLast { core.onJobFinished(token, JobResult.TornDown) }
                    } else {
                        executor.submitTeardown(e.token, h.kernelRuntime, e.soft, ::onJobStep, ::onJobDone)
                    }
                }

                is Effect.CancelJob -> executor.cancel(e.token)

                is Effect.SetTimer -> {
                    val key = e.key
                    platform.schedule(key.slot, e.delayMs, Runnable { dispatch { core.onTimer(key) } })
                }
                is Effect.CancelTimer -> platform.cancel(e.key.slot)

                is Effect.Persist -> {
                    try {
                        store.saveDesired(e.desired)
                        e.spec?.let(store::saveSpec)
                    } catch (t: Throwable) {
                        platform.log("persist failed: $t")
                    }
                    // 引用集合以存储的真实内容为准（写入失败时旧 spec 仍在存储里）。
                    if (e.spec != null) {
                        val (path, known) = readStoredSpecPath()
                        queue.addLast { core.onSpecStored(path, known) }
                    }
                }

                is Effect.NoticeStarting -> handles[e.inst]?.noticeStarting(e.profileName)
                is Effect.NoticeStarted -> handles[e.inst]?.noticeStarted(e.profileName)
                is Effect.NoticeStopUpdates -> handles[e.inst]?.noticeStopUpdates()
            }
        }
    }

    /** 存储里持久化 spec 的路径（外部入口在冷进程里读的就是它）；读取失败 = 未知。 */
    private fun readStoredSpecPath(): Pair<String?, Boolean> = try {
        store.loadSpec()?.runtimeConfigPath to true
    } catch (t: Throwable) {
        platform.log("load stored spec failed: $t")
        null to false
    }

    // 执行层回调（已经在主线程）。
    private fun onJobStep(token: Long, name: String) = dispatch { core.onJobStep(token, name) }

    private fun onJobDone(token: Long, result: JobResult) = dispatch { core.onJobFinished(token, result) }

    companion object {
        private val wiring by lazy { AndroidKernelWiring() }

        /** 进程级单例。 */
        val instance: KernelCoordinator get() = wiring.coordinator

        /** 进程级快照 LiveData（只在主线程 setValue）。 */
        val snapshotLive: androidx.lifecycle.LiveData<KernelSnapshot> get() = wiring.live

        fun attachActivity(host: ActivityHost) = wiring.platform.attachActivity(host)
        fun detachActivity(host: ActivityHost) = wiring.platform.detachActivity(host)

        /** VPN 授权对话框的结果，按弹窗的 requestCode 归属；false = 不是授权对话框的 requestCode。 */
        fun onVpnConsentResult(requestCode: Int, granted: Boolean): Boolean =
            VpnConsentBroker.owns(requestCode) && wiring.platform.onConsentResult(requestCode, granted)
    }
}
