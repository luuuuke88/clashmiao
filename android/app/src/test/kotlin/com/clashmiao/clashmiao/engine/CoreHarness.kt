package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

/**
 * [CoordinatorCore] 的测试脚手架：模拟「主线程执行动作 → 结果当作新事件喂回核心」。
 *
 * 非执行层的动作可自动回应（授权、拉起 Service、销毁 Service），执行层任务（RunStart/RunTeardown）
 * 一律由测试手动 [finishJob]，这样每个用例能精确控制阻塞与返回的时机。
 *
 * 每一步都校验不变量：
 *  - 执行层同一时刻至多一个任务；
 *  - 只有一个内核实例：RunStart 之前所有 runtime 都必须已回收；
 *  - 退休 Service 之前它的 runtime 必须已回收；
 *  - epoch 恒定，version/attempt 单调不减，字段变化时 version 恰好 +1。
 */
class CoreHarness(
    var mode: ServiceType = ServiceType.Vpn,
    var autoAuth: Boolean = true,
    var autoService: Boolean = true,
    var autoDestroy: Boolean = true,
    /** 持久化动作自动以「确认落盘」回应。 */
    var autoPersist: Boolean = true,
    config: CoordinatorCore.Config = CoordinatorCore.Config(),
) {
    data class InFlight(val token: Long, val inst: Int, val isStart: Boolean, val soft: Boolean)

    val core = CoordinatorCore("epoch-A", { mode }, config)
    val effects = ArrayList<Effect>()
    val snapshots = arrayListOf(core.snapshot)
    var inFlight: InFlight? = null
        private set
    val timers = HashMap<Pair<TimerKind, Long>, TimerKey>()
    private val dirty = HashSet<Int>()
    private val queue = ArrayDeque<() -> CoreStep>()
    private var draining = false
    var nextInst = 1
    val startedServices = ArrayList<Pair<Int, ServiceType>>()
    val startIds = HashMap<Int, Int>()

    val snap get() = core.snapshot

    fun spec(rev: Long, name: String = "p$rev") =
        LaunchSpec("/cfg/runtime-$rev.json", "{\"r\":$rev}", name, rev)

    // --- 事件注入（每个都会跑完自动回应的连锁）---

    fun request(
        seq: Long,
        desired: Desired,
        rev: Long = 1,
        epoch: String? = "epoch-A",
    ): Receipt {
        var receipt: Receipt? = null
        run {
            val s = core.onRequest(epoch, seq, desired, if (desired == Desired.On) spec(rev) else null)
            receipt = s.receipt
            s
        }
        return receipt!!
    }

    fun on(seq: Long, rev: Long = 1) = request(seq, Desired.On, rev)
    fun off(seq: Long) = request(seq, Desired.Off)

    fun external(src: Source, desired: Desired, fallback: LaunchSpec? = null) =
        run { core.onExternal(src, desired, fallback) }

    fun finishJob(result: JobResult) {
        val j = checkNotNull(inFlight) { "no job in flight" }
        // 从执行层视角任务已经结束；teardown 完成 = 该实例 runtime 干净。
        inFlight = null
        if (!j.isStart) dirty -= j.inst
        run { core.onJobFinished(j.token, result) }
    }

    /** 以「teardown 完成」结束当前任务。 */
    fun finishTeardown() = finishJob(JobResult.TornDown)

    fun serviceStarted(inst: Int, type: ServiceType, startId: Int): CoreStep {
        startIds[inst] = maxOf(startIds[inst] ?: 0, startId)
        return run { core.onServiceStarted(inst, type, startId) }
    }

    fun serviceDestroyed(inst: Int) = run { core.onServiceDestroyed(inst) }
    fun revoked(inst: Int) = run { core.onServiceRevoked(inst) }
    fun authResult(token: Long, granted: Boolean) = run { core.onAuthResult(token, granted) }
    fun jobStep(name: String) = run { core.onJobStep(checkNotNull(inFlight).token, name) }
    fun ack(attempt: Long) = run { core.onAckReplay(attempt) }
    fun network(handle: Long) = run { core.onNetworkResolved(handle) }
    fun reloadRequested(src: Source) = run { core.onReloadRequested(src) }

    fun fire(kind: TimerKind, subject: Long? = null) {
        val key = timers.entries.firstOrNull { it.key.first == kind && (subject == null || it.value.subject == subject) }
            ?.value
            ?: error("no $kind timer armed; armed=${timers.values}")
        timers.remove(key.slot)
        run { core.onTimer(key) }
    }

    fun fireStale(key: TimerKey) = run { core.onTimer(key) }

    // --- 查询 ---

    inline fun <reified T : Effect> all(): List<T> = effects.filterIsInstance<T>()
    inline fun <reified T : Effect> last(): T = all<T>().last()
    inline fun <reified T : Effect> count(): Int = all<T>().size
    fun mark(): Int = effects.size
    inline fun <reified T : Effect> since(mark: Int): List<T> =
        effects.drop(mark).filterIsInstance<T>()

    val statuses get() = snapshots.map { it.status }

    fun assertSnap(
        status: KernelStatus? = null,
        desired: Desired? = null,
        attempt: Long? = null,
        source: Source? = null,
        rev: Long? = null,
        replay: Boolean? = null,
    ) {
        val s = snap
        if (status != null) assertEquals("status", status, s.status)
        if (desired != null) assertEquals("desired", desired, s.desired)
        if (attempt != null) assertEquals("attempt", attempt, s.attempt)
        if (source != null) assertEquals("source", source, s.source)
        if (rev != null) assertEquals("activeConfigRevision", rev, s.activeConfigRevision)
        if (replay != null) assertEquals("replay", replay, s.selectionsReplayNeeded)
    }

    fun assertNoRev() = assertNull(snap.activeConfigRevision)

    // --- 内部：执行动作并校验不变量 ---

    private fun run(block: () -> CoreStep): CoreStep {
        var first: CoreStep? = null
        queue.addLast {
            val s = block()
            if (first == null) first = s
            s
        }
        drain()
        return first!!
    }

    private fun drain() {
        if (draining) return
        draining = true
        try {
            while (queue.isNotEmpty()) {
                val step = queue.removeFirst()()
                observe(step)
            }
        } finally {
            draining = false
        }
    }

    private fun observe(step: CoreStep) {
        // 快照不变量
        val now = core.snapshot
        val prev = snapshots.last()
        assertEquals("epoch constant", "epoch-A", now.epoch)
        if (now != prev) {
            assertEquals("version +1 on change", prev.version + 1, now.version)
            snapshots += now
        } else {
            assertEquals(prev.version, now.version)
        }
        assertTrue("attempt monotonic", now.attempt >= prev.attempt)

        for (e in step.effects) {
            effects += e
            when (e) {
                is Effect.SetTimer -> timers[e.key.slot] = e.key
                is Effect.CancelTimer -> timers.remove(e.key.slot)
                is Effect.RunStart -> {
                    check(inFlight == null) { "two jobs in flight: $inFlight + $e" }
                    check(dirty.isEmpty()) { "second kernel started while $dirty not torn down" }
                    dirty += e.inst
                    inFlight = InFlight(e.token, e.inst, isStart = true, soft = false)
                }
                is Effect.RunTeardown -> {
                    check(inFlight == null) { "two jobs in flight: $inFlight + $e" }
                    inFlight = InFlight(e.token, e.inst, isStart = false, soft = e.soft)
                }
                is Effect.RetireService -> {
                    check(e.inst !in dirty) { "retired instance ${e.inst} before its runtime was torn down" }
                    check(inFlight?.inst != e.inst) { "retired instance ${e.inst} with a job in flight" }
                    val maxId = startIds[e.inst] ?: 0
                    assertEquals("stopSelfResult uses the instance's own max startId", maxId, e.maxStartId)
                    if (autoDestroy) queue.addLast { core.onServiceDestroyed(e.inst) }
                }
                is Effect.Persist -> if (autoPersist) queue.addLast { core.onPersistResult(e.serial, true) }
                is Effect.RequestAuth -> if (autoAuth) queue.addLast { core.onAuthResult(e.token, true) }
                is Effect.StartService -> if (autoService) {
                    val inst = nextInst++
                    startedServices += inst to e.type
                    startIds[inst] = 1
                    queue.addLast { core.onServiceStarted(inst, e.type, 1) }
                }
                else -> Unit
            }
        }
    }

    /** 测试结束时的通用断言：没有残留任务。 */
    fun assertQuiescent() {
        check(inFlight == null) { "job still in flight: $inFlight" }
    }
}
