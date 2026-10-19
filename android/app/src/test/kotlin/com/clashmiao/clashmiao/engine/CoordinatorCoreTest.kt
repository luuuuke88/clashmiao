package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * spec §8「CoordinatorCore」清单 + §10.1/10.2/10.4/10.7 的逐条覆盖。
 * 脚手架见 [CoreHarness]（每一步都校验「单任务」「单内核」「先回收再退休」等不变量）。
 */
class CoordinatorCoreTest {

    private fun CoreHarness.connected(seq: Long = 1, rev: Long = 1) {
        on(seq, rev)
        assertTrue(inFlight!!.isStart)
        finishJob(JobResult.Started)
        assertSnap(status = KernelStatus.Started)
    }

    // ========================================================================
    //  基本生命周期
    // ========================================================================

    @Test
    fun `VPN 模式连接序列 授权 拉起 Service 启动 就绪`() {
        val h = CoreHarness(ServiceType.Vpn)
        val receipt = h.on(1, rev = 7)
        assertTrue(receipt.accepted)
        assertEquals(1L, receipt.appliedSeq)
        // 授权与 Service 都被自动回应，执行层任务已派发
        assertEquals(1, h.count<Effect.RequestAuth>())
        assertEquals(listOf(1 to ServiceType.Vpn), h.startedServices)
        val start = h.last<Effect.RunStart>()
        assertEquals(h.spec(7), start.spec)
        assertFalse(start.reload)
        h.assertSnap(
            status = KernelStatus.Starting, desired = Desired.On, attempt = 1,
            source = Source.App, replay = false,
        )
        assertNull(h.snap.activeConfigRevision)
        assertEquals(1L, h.snap.appliedSeq)

        h.finishJob(JobResult.Started)
        h.assertSnap(
            status = KernelStatus.Started, attempt = 1, rev = 7, replay = true,
        )
        val started = h.last<Effect.NoticeStarted>()
        assertEquals("p7", started.profileName)
        // 没有残留的启动超时
        assertFalse(h.timers.containsKey(TimerKind.StartTimeout to 0L))
        h.assertQuiescent()
    }

    @Test
    fun `Proxy 模式不请求授权`() {
        val h = CoreHarness(ServiceType.Proxy)
        h.on(1)
        assertEquals(0, h.count<Effect.RequestAuth>())
        assertEquals(listOf(1 to ServiceType.Proxy), h.startedServices)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started)
    }

    @Test
    fun `断开 先回收运行时 再对该实例 stopSelfResult 最后 onDestroy 才算退休`() {
        val h = CoreHarness()
        h.connected()
        val m = h.mark()
        h.off(2)
        // off 到达的同一时刻就发布 stopping，并派发完整回收
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        assertNull(h.snap.activeConfigRevision)
        assertFalse(h.snap.selectionsReplayNeeded)
        val td = h.since<Effect.RunTeardown>(m).single()
        assertFalse(td.soft)
        assertEquals(0, h.since<Effect.RetireService>(m).size)

        h.finishTeardown()
        assertEquals(KernelStatus.Stopped, h.snap.status)
        val retire = h.since<Effect.RetireService>(m).single()
        assertEquals(1, retire.inst)
        assertEquals(1, retire.maxStartId)
        h.assertQuiescent()
    }

    @Test
    fun `Stopped 只在运行时回收之后才发布 退休等 onDestroy 不阻塞状态`() {
        val h = CoreHarness(autoDestroy = false)
        h.connected()
        h.off(2)
        h.finishTeardown()
        // 回收完成即 stopped，哪怕 Service 还没销毁
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals(1, h.count<Effect.RetireService>())
        h.serviceDestroyed(1)
        h.assertSnap(status = KernelStatus.Stopped)
    }

    @Test
    fun `重复的 on 请求在已就绪且 revision 相同时是空操作`() {
        val h = CoreHarness()
        h.connected(rev = 3)
        val before = h.snap
        val m = h.mark()
        h.on(2, rev = 3)
        assertEquals(0, h.since<Effect.RunStart>(m).size)
        assertEquals(0, h.since<Effect.RunTeardown>(m).size)
        assertEquals(0, h.since<Effect.StartService>(m).size)
        assertEquals(before.attempt, h.snap.attempt)
        assertEquals(KernelStatus.Started, h.snap.status)
        assertEquals(2L, h.snap.appliedSeq)
    }

    // ========================================================================
    //  请求覆盖（on→off→on 快速连发只执行最后一个）
    // ========================================================================

    @Test
    fun `授权等待中 on off on 只保留最后一次 旧授权回调被丢弃`() {
        val h = CoreHarness(autoAuth = false)
        h.on(1)
        val t1 = h.last<Effect.RequestAuth>().token
        h.off(2)
        assertEquals(1, h.count<Effect.CancelAuth>())
        // 没有任何东西在运行：off 立即就是 stopped
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
        h.on(3)
        val t2 = h.last<Effect.RequestAuth>().token
        assertTrue(t2 != t1)

        // 第一次请求对应的授权结果迟到：不得启动任何东西
        h.authResult(t1, true)
        assertEquals(0, h.count<Effect.StartService>())
        h.authResult(t2, true)
        assertEquals(1, h.count<Effect.StartService>())
        h.assertSnap(desired = Desired.On, attempt = 2)
        h.finishJob(JobResult.Started)
        assertEquals(1, h.startedServices.size)
    }

    @Test
    fun `授权等待中又来了新的 on 新请求自己重新检查授权 旧 token 的结果不再作数`() {
        // 平台层保证不重复弹窗（见 VpnConsentBrokerTest）；核心只认当前请求的 token。
        val h = CoreHarness(autoAuth = false)
        h.on(1, rev = 1)
        val t1 = h.last<Effect.RequestAuth>().token
        h.on(2, rev = 2)
        assertEquals(listOf(t1), h.all<Effect.CancelAuth>().map { it.token })
        val t2 = h.last<Effect.RequestAuth>().token
        assertTrue(t2 != t1)
        // 旧弹窗的结果只属于 t1：被丢弃，既不启动也不让 seq=2 失败
        h.authResult(t1, false)
        assertNull(h.snap.lastFailure)
        assertEquals(0, h.count<Effect.StartService>())
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        h.authResult(t2, true)
        // 启动使用最新的 spec
        assertEquals(2L, h.last<Effect.RunStart>().spec.configRevision)
    }

    @Test
    fun `启动阻塞中 on off on 不并发 回收后用最新意图重启 单内核`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        val firstJob = h.inFlight!!
        // off：立即 stopping，给任务打取消标，不派发回收（任务还在阻塞）
        val m = h.mark()
        h.off(2)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        assertEquals(listOf(firstJob.token), h.since<Effect.CancelJob>(m).map { it.token })
        assertEquals(0, h.since<Effect.RunTeardown>(m).size)
        // on：仍然不能并发；意图记下，状态回到 starting
        h.on(3, rev = 1)
        h.assertSnap(status = KernelStatus.Starting, desired = Desired.On)
        assertEquals(firstJob, h.inFlight)
        assertEquals(0, h.since<Effect.RunStart>(m).size)

        // 阻塞调用返回（取消）：先补回收局部资源，再启动一次
        h.finishJob(JobResult.Cancelled)
        val td = h.last<Effect.RunTeardown>()
        assertTrue("同类 Service 复用，软回收即可", td.soft)
        h.finishTeardown()
        val second = h.last<Effect.RunStart>()
        assertTrue(second.token != firstJob.token)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2)
        assertEquals(1, h.startedServices.size)
        h.assertQuiescent()
    }

    // ========================================================================
    //  启动阻塞中收到 off（含尚未移交的局部实例）
    // ========================================================================

    @Test
    fun `启动阻塞中收到 off 立即 stopping 返回后不再继续 完整回收后 stopped`() {
        val h = CoreHarness()
        h.on(1)
        h.assertSnap(status = KernelStatus.Starting)
        h.off(2)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        // 阻塞调用返回，runtime 报告取消（局部实例在 runtime 名下）
        h.finishJob(JobResult.Cancelled)
        val td = h.last<Effect.RunTeardown>()
        assertFalse("停止要完整回收", td.soft)
        h.assertSnap(status = KernelStatus.Stopping)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
        assertEquals(1, h.count<Effect.RetireService>())
        assertNull(h.snap.lastFailure)
    }

    @Test
    fun `启动其实已经成功才收到 off 的竞态 同样完整回收`() {
        val h = CoreHarness()
        h.on(1)
        h.off(2)
        h.finishJob(JobResult.Started) // 取消标没赶上
        h.assertSnap(status = KernelStatus.Stopping)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertNull(h.snap.activeConfigRevision)
        assertEquals(0, h.count<Effect.NoticeStarted>())
    }

    @Test
    fun `启动失败返回时已被 off 取代 不写 failure`() {
        val h = CoreHarness()
        h.on(1)
        h.off(2)
        h.finishJob(JobResult.Failed(FailureCode.StartService, "boom"))
        h.finishTeardown()
        assertNull(h.snap.lastFailure)
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
    }

    @Test
    fun `停止在任何阶段都会被执行`() {
        // 阶段 1：等授权
        run {
            val h = CoreHarness(autoAuth = false)
            h.on(1)
            h.off(2)
            h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
        }
        // 阶段 2：Service 已请求拉起、尚未到达 —— 到达后被当作孤儿退休
        run {
            val h = CoreHarness(autoService = false)
            h.on(1)
            assertEquals(1, h.count<Effect.StartService>())
            h.off(2)
            h.assertSnap(status = KernelStatus.Stopped)
            h.serviceStarted(5, ServiceType.Vpn, 1)
            assertEquals(5, h.last<Effect.RetireService>().inst)
            h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
        }
        // 阶段 3：启动任务阻塞中
        run {
            val h = CoreHarness()
            h.on(1)
            h.off(2)
            h.assertSnap(status = KernelStatus.Stopping)
            h.finishJob(JobResult.Cancelled)
            h.finishTeardown()
            h.assertSnap(status = KernelStatus.Stopped)
        }
        // 阶段 4：已就绪
        run {
            val h = CoreHarness()
            h.connected()
            h.off(2)
            h.finishTeardown()
            h.assertSnap(status = KernelStatus.Stopped)
        }
        // 阶段 5：重载的回收阶段
        run {
            val h = CoreHarness()
            h.connected(rev = 1)
            h.on(2, rev = 2)
            assertFalse(h.inFlight!!.isStart) // 正在软回收
            h.off(3)
            h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
            h.finishTeardown()
            // 软回收之后仍有 command server：必须再补一次完整回收
            assertFalse(h.last<Effect.RunTeardown>().soft)
            h.finishTeardown()
            h.assertSnap(status = KernelStatus.Stopped)
            assertEquals(0, h.count<Effect.RunStart>() - 1)
        }
    }

    // ========================================================================
    //  失败 / 超时
    // ========================================================================

    @Test
    fun `启动失败 desired 置 off 写 failure 归属请求序号 回收后 stopped`() {
        val h = CoreHarness()
        h.on(4)
        h.finishJob(JobResult.Failed(FailureCode.CreateService, "no tun"))
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.CreateService, f.code)
        assertEquals("no tun", f.message)
        assertEquals(1L, f.attempt)
        assertEquals(4L, f.seq)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        // failure 不会被后续回收清掉
        assertNotNull(h.snap.lastFailure)
        // 持久化 desired 同步置 off
        assertEquals(Desired.Off, h.last<Effect.Persist>().desired)
    }

    @Test
    fun `授权被拒 permissionDenied 且不会拉起 Service`() {
        val h = CoreHarness(autoAuth = false)
        h.on(1)
        h.authResult(h.last<Effect.RequestAuth>().token, false)
        assertEquals(0, h.count<Effect.StartService>())
        assertEquals(FailureCode.PermissionDenied, h.snap.lastFailure!!.code)
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
    }

    @Test
    fun `启动超时 30s 含授权等待 desired off 加 failure`() {
        val h = CoreHarness(autoAuth = false)
        h.on(1)
        val key = h.timers[TimerKind.StartTimeout to 0L]!!
        assertEquals(30_000L, h.effects.filterIsInstance<Effect.SetTimer>().first { it.key == key }.delayMs)
        h.fire(TimerKind.StartTimeout)
        assertEquals(FailureCode.StartTimeout, h.snap.lastFailure!!.code)
        assertEquals(1L, h.snap.lastFailure!!.seq)
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
    }

    @Test
    fun `启动超时发生在阻塞调用里 状态如实保持 stopping 返回后回收`() {
        val h = CoreHarness()
        h.on(1)
        h.fire(TimerKind.StartTimeout)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        assertEquals(FailureCode.StartTimeout, h.snap.lastFailure!!.code)
        assertEquals(1, h.count<Effect.CancelJob>())
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals(FailureCode.StartTimeout, h.snap.lastFailure!!.code)
    }

    @Test
    fun `启动超时的定时器在启动成功后触发 无效`() {
        val h = CoreHarness()
        h.on(1)
        val key = h.timers[TimerKind.StartTimeout to 0L]!!
        h.finishJob(JobResult.Started)
        h.fireStale(key)
        h.assertSnap(status = KernelStatus.Started, desired = Desired.On)
        assertNull(h.snap.lastFailure)
    }

    @Test
    fun `单个阻塞调用超 20s 写 kernelUnresponsive 状态保持 stopping 返回后照常回收`() {
        val h = CoreHarness()
        h.on(1)
        h.jobStep("newService")
        h.off(2)
        h.assertSnap(status = KernelStatus.Stopping)
        val key = h.timers[TimerKind.Watchdog to 0L]!!
        assertEquals(20_000L, h.effects.filterIsInstance<Effect.SetTimer>().last { it.key == key }.delayMs)
        h.fire(TimerKind.Watchdog)
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.KernelUnresponsive, f.code)
        assertEquals("失败归属到当前的 off 请求", 2L, f.seq)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        // 调用终于返回
        h.finishJob(JobResult.Cancelled)
        h.assertSnap(status = KernelStatus.Stopping)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals(FailureCode.KernelUnresponsive, h.snap.lastFailure!!.code)
    }

    @Test
    fun `启动卡住 20s 而 desired 仍是 on 放弃并置 off`() {
        val h = CoreHarness()
        h.on(1)
        h.jobStep("start")
        h.fire(TimerKind.Watchdog)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
        assertEquals(FailureCode.KernelUnresponsive, h.snap.lastFailure!!.code)
        assertEquals(1L, h.snap.lastFailure!!.seq)
        assertEquals(1, h.count<Effect.CancelJob>())
    }

    @Test
    fun `看门狗只对仍停在同一步骤的任务有效`() {
        val h = CoreHarness()
        h.on(1)
        h.jobStep("a")
        val stale = h.timers[TimerKind.Watchdog to 0L]!!
        h.jobStep("b") // 上一步已经返回
        h.fireStale(stale)
        assertNull(h.snap.lastFailure)
        h.assertSnap(status = KernelStatus.Starting, desired = Desired.On)
        h.finishJob(JobResult.Started)
        h.fireStale(h.timers[TimerKind.Watchdog to 0L] ?: stale)
        assertNull(h.snap.lastFailure)
    }

    @Test
    fun `卡住期间重发 off 把失败归属改到新请求`() {
        val h = CoreHarness()
        h.on(1)
        h.jobStep("start")
        h.off(2)
        h.fire(TimerKind.Watchdog)
        assertEquals(2L, h.snap.lastFailure!!.seq)
        h.off(3)
        assertEquals(3L, h.snap.lastFailure!!.seq)
        assertEquals(1, h.count<Effect.CancelJob>())
    }

    // ========================================================================
    //  执行 token 归属（§10.2）
    // ========================================================================

    @Test
    fun `旧执行的失败不改新 desired 且新意图随后用新配置启动`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        h.on(2, rev = 2) // 意图变了，旧序列已在阻塞调用里
        h.assertSnap(desired = Desired.On)
        h.finishJob(JobResult.Failed(FailureCode.StartService, "old spec exploded"))
        // 旧失败只回收，不改 desired，不写 failure；失败可能留下半初始化资源 → 完整回收
        assertNull(h.snap.lastFailure)
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        assertEquals(2L, h.last<Effect.RunStart>().spec.configRevision)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, attempt = 2)
    }

    @Test
    fun `引用集合 在途启动任务读的文件在任务返回前一直被声明 即使意图已换`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        assertEquals(listOf("/cfg/runtime-1.json"), h.snap.retainedConfigPaths)
        h.on(2, rev = 2) // 旧任务已打取消标，但仍在阻塞调用里，随时可能读文件
        assertEquals(listOf("/cfg/runtime-1.json", "/cfg/runtime-2.json"), h.snap.retainedConfigPaths)
        h.off(3)
        assertEquals(
            "停止也一样：任务没返回，它的文件不能放",
            listOf("/cfg/runtime-1.json", "/cfg/runtime-2.json"),
            h.snap.retainedConfigPaths,
        )
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals(
            "任务返回后只剩当前意图的 spec（本用例未模拟持久化回读）",
            listOf("/cfg/runtime-2.json"),
            h.snap.retainedConfigPaths,
        )
        assertTrue(h.snapshots.all { it.retainedConfigPaths != null })
    }

    @Test
    fun `引用集合 构造时的持久化路径进首份快照 回读结果按存储更新`() {
        val core = CoordinatorCore("e", { ServiceType.Vpn }, storedSpecPath = "/w/runtime-9.json")
        assertEquals(1L, core.snapshot.version)
        assertEquals(listOf("/w/runtime-9.json"), core.snapshot.retainedConfigPaths)
        core.onSpecStored("/w/runtime-10.json")
        assertEquals(listOf("/w/runtime-10.json"), core.snapshot.retainedConfigPaths)
        core.onSpecStored(null, known = false)
        assertNull(core.snapshot.retainedConfigPaths)
        core.onSpecStored(null)
        assertEquals(emptyList<String>(), core.snapshot.retainedConfigPaths)
    }

    @Test
    fun `旧执行启动成功但意图已变 不发布过时的 started 直接重载到新 revision`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        h.on(2, rev = 2)
        h.finishJob(JobResult.Started)
        // revision 1 从未以 started 对外发布
        assertTrue(h.snapshots.none { it.status == KernelStatus.Started && it.activeConfigRevision == 1L })
        assertTrue(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        assertTrue("重载紧随回收", h.last<Effect.RunStart>().reload)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, attempt = 2, replay = true)
    }

    @Test
    fun `旧执行的启动超时不改新 desired`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        val oldTimeout = h.timers[TimerKind.StartTimeout to 0L]!!
        h.on(2, rev = 2)
        h.fireStale(oldTimeout)
        assertNull(h.snap.lastFailure)
        h.assertSnap(desired = Desired.On)
        // 旧序列被放弃（取消标），新意图随后启动
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2)
    }

    @Test
    fun `同 revision 的新 seq 是新请求 旧执行的失败不归它 由它自己的一次启动终结`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        val m = h.mark()
        h.on(2, rev = 1) // 同 revision：配置去重，在途启动继续跑（不取消）
        assertEquals(0, h.since<Effect.CancelJob>(m).size)
        h.finishJob(JobResult.Failed(FailureCode.StartService, "old failure"))
        // seq=1 的失败不写给 seq=2，也不关 desired
        assertNull(h.snap.lastFailure)
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        // seq=2 自己的序列：先完整回收失败启动留下的资源（不复用半初始化的 command server），再启动一次
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        assertEquals(2, h.count<Effect.RunStart>())
        h.assertSnap(attempt = 2)
        h.finishJob(JobResult.Failed(FailureCode.StartService, "real failure"))
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.StartService, f.code)
        assertEquals("失败归属它自己的 seq", 2L, f.seq)
        assertEquals(2L, f.attempt)
        h.assertSnap(desired = Desired.Off)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals("有限的请求只换来有限的尝试", 2, h.count<Effect.RunStart>())
    }

    @Test
    fun `同 revision 的新 seq 沿用在途启动的成功 内核无操作 attempt 不变 以 started 终结`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        h.on(2, rev = 1)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, desired = Desired.On, attempt = 1, rev = 1, replay = true)
        assertEquals(2L, h.snap.appliedSeq)
        assertNull(h.snap.lastFailure)
        assertEquals(1, h.count<Effect.RunStart>())
        assertFalse("seq=2 的启动超时随之撤销", h.timers.containsKey(TimerKind.StartTimeout to 0L))
    }

    @Test
    fun `同 revision 的新 seq 旧序列的启动超时不作数 新 seq 的超时只写给它自己`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        val oldTimeout = h.timers[TimerKind.StartTimeout to 0L]!!
        h.on(2, rev = 1)
        val newTimeout = h.timers[TimerKind.StartTimeout to 0L]!!
        assertTrue(oldTimeout != newTimeout)
        h.fireStale(oldTimeout)
        assertNull(h.snap.lastFailure)
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        h.fire(TimerKind.StartTimeout)
        assertEquals(FailureCode.StartTimeout, h.snap.lastFailure!!.code)
        assertEquals(2L, h.snap.lastFailure!!.seq)
        h.assertSnap(desired = Desired.Off, status = KernelStatus.Stopping)
    }

    @Test
    fun `同 revision 的新 seq 旧授权被拒也不会让新请求失败 新请求只按自己的授权结果终结`() {
        val h = CoreHarness(autoAuth = false)
        h.on(1, rev = 1)
        val t1 = h.last<Effect.RequestAuth>().token
        h.on(2, rev = 1)
        val t2 = h.last<Effect.RequestAuth>().token
        h.authResult(t1, false)
        assertNull(h.snap.lastFailure)
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        h.authResult(t2, false)
        assertEquals(FailureCode.PermissionDenied, h.snap.lastFailure!!.code)
        assertEquals(2L, h.snap.lastFailure!!.seq)
        h.assertSnap(desired = Desired.Off, status = KernelStatus.Stopped)
    }

    // ------------------------------------------------------------------------
    //  过时执行的看门狗 / 回收超时（审核问题 1）
    // ------------------------------------------------------------------------

    @Test
    fun `旧执行的看门狗不会关掉最新的 on 序列 on1 阻塞 off2 on3`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        h.jobStep("start")
        h.off(2)
        h.on(3, rev = 1)
        h.assertSnap(status = KernelStatus.Starting, desired = Desired.On)
        h.fire(TimerKind.Watchdog) // seq=1 的任务卡住超过 20 s
        h.assertSnap(status = KernelStatus.Starting, desired = Desired.On)
        assertNull("不写 seq=3 的失败", h.snap.lastFailure)
        // 阻塞调用终于返回：seq=3 按自己的序列继续
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, desired = Desired.On, attempt = 2)
        assertNull(h.snap.lastFailure)
    }

    @Test
    fun `旧执行一直卡死 最新的 on 由它自己的 30s 启动超时终结`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        h.jobStep("start")
        h.off(2)
        h.on(3, rev = 1)
        h.fire(TimerKind.Watchdog)
        h.assertSnap(desired = Desired.On)
        h.fire(TimerKind.StartTimeout)
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.StartTimeout, f.code)
        assertEquals(3L, f.seq)
        // 内核仍卡着：如实 stopping，调用返回后照常回收
        h.assertSnap(desired = Desired.Off, status = KernelStatus.Stopping)
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        assertEquals(3L, h.snap.lastFailure!!.seq)
    }

    @Test
    fun `旧回收任务卡住超时 不关掉之后的 on`() {
        val h = CoreHarness()
        h.connected(seq = 1)
        h.off(2)
        assertFalse(h.inFlight!!.isStart)
        h.jobStep("closeService")
        h.on(3)
        h.fire(TimerKind.Watchdog) // seq=2 的回收卡住
        h.assertSnap(desired = Desired.On, status = KernelStatus.Starting)
        assertNull(h.snap.lastFailure)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2)
        assertNull(h.snap.lastFailure)
    }

    @Test
    fun `当前请求自己的重载回收卡住 当前请求失败`() {
        val h = CoreHarness()
        h.connected(rev = 1)
        h.on(2, rev = 2)
        assertTrue(h.inFlight!!.soft)
        h.jobStep("closeService")
        h.fire(TimerKind.Watchdog)
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.KernelUnresponsive, f.code)
        assertEquals(2L, f.seq)
        h.assertSnap(desired = Desired.Off, status = KernelStatus.Stopping)
    }

    @Test
    fun `失败之后重新点连接 开新序列 attempt 递增`() {
        val h = CoreHarness()
        h.on(1)
        h.finishJob(JobResult.Failed(FailureCode.StartService, "x"))
        h.finishTeardown()
        h.on(2)
        h.assertSnap(desired = Desired.On, attempt = 2)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2)
        assertEquals("旧 failure 仍归属 attempt 1", 1L, h.snap.lastFailure!!.attempt)
    }

    // ========================================================================
    //  配置 revision / 重载
    // ========================================================================

    @Test
    fun `revision 变化触发重载 软回收 再启动 attempt 加一`() {
        val h = CoreHarness()
        h.connected(rev = 1)
        h.on(2, rev = 2)
        h.assertSnap(status = KernelStatus.Starting, attempt = 2, replay = false)
        assertNull(h.snap.activeConfigRevision)
        val td = h.last<Effect.RunTeardown>()
        assertTrue(td.soft)
        assertEquals(1, h.count<Effect.StartService>())
        h.finishTeardown()
        val st = h.last<Effect.RunStart>()
        assertTrue(st.reload)
        assertEquals(h.last<Effect.RunStart>().inst, td.inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, attempt = 2, replay = true)
        assertEquals("重载不换 Service 实例", 1, h.startedServices.size)
    }

    @Test
    fun `重载失败 desired off 写 failure 完整回收`() {
        val h = CoreHarness()
        h.connected(rev = 1)
        h.on(2, rev = 2)
        h.finishTeardown()
        h.finishJob(JobResult.Failed(FailureCode.CreateService, "bad config"))
        assertEquals(2L, h.snap.lastFailure!!.attempt)
        assertEquals(2L, h.snap.lastFailure!!.seq)
        h.assertSnap(desired = Desired.Off)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
    }

    @Test
    fun `libbox 的 serviceReload 回调转成 source system 的重载请求`() {
        val h = CoreHarness()
        h.connected()
        h.reloadRequested(Source.System)
        h.assertSnap(status = KernelStatus.Starting, attempt = 2, source = Source.System, desired = Desired.On)
        assertTrue(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2, source = Source.System)
    }

    @Test
    fun `启动中或已关闭时的 reload 请求被忽略`() {
        val h = CoreHarness()
        h.reloadRequested(Source.System)
        assertEquals(0L, h.snap.attempt)
        h.on(1)
        h.reloadRequested(Source.System)
        h.assertSnap(source = Source.App)
        h.finishJob(JobResult.Started)
        assertEquals(1L, h.snap.attempt)
    }

    // ========================================================================
    //  换 Service 类（§10.4）
    // ========================================================================

    @Test
    fun `换类 先回收 再退休旧实例 onDestroy 之后才起新 Service`() {
        val h = CoreHarness(ServiceType.Vpn, autoDestroy = false)
        h.connected(rev = 1)
        h.mode = ServiceType.Proxy
        val m = h.mark()
        h.on(2, rev = 2)
        // 1. 先完整回收旧运行时（不是软回收：换类）
        val td = h.since<Effect.RunTeardown>(m).single()
        assertFalse(td.soft)
        h.assertSnap(status = KernelStatus.Starting, attempt = 2)
        assertEquals(0, h.since<Effect.RetireService>(m).size)
        h.finishTeardown()
        // 2. 对旧实例 stopSelfResult；此时不能起新 Service
        val retire = h.since<Effect.RetireService>(m).single()
        assertEquals(1, retire.inst)
        assertEquals(0, h.since<Effect.StartService>(m).size)
        // 3. 旧实例 onDestroy（事件驱动）→ 才起新 Service（Proxy 无需授权）
        h.serviceDestroyed(1)
        assertEquals(listOf(ServiceType.Proxy), h.since<Effect.StartService>(m).map { it.type })
        assertEquals(0, h.since<Effect.RequestAuth>(m).size)
        // 4. 新实例到达 → 在新实例上启动
        assertEquals(2, h.last<Effect.RunStart>().inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, attempt = 2)
    }

    @Test
    fun `换类期间 stopSelfResult 因更新的 startId 没停下 实例复活后再次退休`() {
        val h = CoreHarness(ServiceType.Vpn, autoDestroy = false)
        h.connected()
        h.mode = ServiceType.Proxy
        h.on(2, rev = 2)
        h.finishTeardown()
        assertEquals(1, h.last<Effect.RetireService>().maxStartId)
        // 系统此前已排队了第二个 start 命令：stopSelfResult(1) 返回 false，随后 onStartCommand(startId=2)
        h.serviceStarted(1, ServiceType.Vpn, 2)
        val r = h.last<Effect.RetireService>()
        assertEquals(2, r.maxStartId)
        assertEquals("不会因此起新 Service", 1, h.count<Effect.StartService>())
        h.serviceDestroyed(1)
        assertEquals(2, h.count<Effect.StartService>())
    }

    @Test
    fun `退休超时 只报告失败 继续跟踪旧实例 绝不越过它起另一类 Service`() {
        val h = CoreHarness(ServiceType.Vpn, autoDestroy = false)
        h.connected()
        h.mode = ServiceType.Proxy
        h.on(2, rev = 2)
        h.finishTeardown()
        assertEquals(1, h.count<Effect.StartService>())
        h.fire(TimerKind.Retire)
        assertEquals("没有真实的 onDestroy 就不起 Proxy", 1, h.count<Effect.StartService>())
        val f = h.snap.lastFailure!!
        assertEquals(FailureCode.StartService, f.code)
        assertEquals(2L, f.seq)
        h.assertSnap(desired = Desired.Off, status = KernelStatus.Stopped)
        assertTrue("仍在跟踪旧实例", h.core.knows(1))

        // 新请求：再催一次旧实例，依然以它真实的 onDestroy 为准
        val retires = h.count<Effect.RetireService>()
        h.on(3, rev = 2)
        assertEquals(retires + 1, h.count<Effect.RetireService>())
        assertEquals(1, h.count<Effect.StartService>())
        h.serviceDestroyed(1)
        assertFalse(h.core.knows(1))
        assertEquals(listOf(ServiceType.Vpn, ServiceType.Proxy), h.all<Effect.StartService>().map { it.type })
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, desired = Desired.On)
    }

    @Test
    fun `全局 off 后退休超时 不算失败 实例仍被跟踪`() {
        val h = CoreHarness(autoDestroy = false)
        h.connected()
        h.off(2)
        h.finishTeardown()
        h.fire(TimerKind.Retire)
        assertNull(h.snap.lastFailure)
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off)
        assertTrue(h.core.knows(1))
        h.serviceDestroyed(1)
        assertFalse(h.core.knows(1))
    }

    // ------------------------------------------------------------------------
    //  Service 形态是意图的一部分（审核问题 4）
    // ------------------------------------------------------------------------

    @Test
    fun `授权等待期间切到 Proxy 同 revision 也重建序列 最终运行在 Proxy Service 上`() {
        val h = CoreHarness(ServiceType.Vpn, autoAuth = false)
        h.on(1, rev = 1)
        val t1 = h.last<Effect.RequestAuth>().token
        h.mode = ServiceType.Proxy
        h.on(2, rev = 1)
        assertEquals(listOf(ServiceType.Proxy), h.all<Effect.StartService>().map { it.type })
        h.authResult(t1, true) // 迟到的旧授权：丢弃
        assertEquals(1, h.count<Effect.StartService>())
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, desired = Desired.On)
        assertEquals(listOf(1 to ServiceType.Proxy), h.startedServices)
    }

    @Test
    fun `Service 未到达时从 Vpn 切到 Proxy 先等它到达并退休 销毁后才起 Proxy`() {
        val h = CoreHarness(ServiceType.Vpn, autoService = false, autoDestroy = false)
        h.on(1)
        assertEquals(listOf(ServiceType.Vpn), h.all<Effect.StartService>().map { it.type })
        h.mode = ServiceType.Proxy
        h.on(2, rev = 2)
        assertEquals("Vpn 还没到达：不能同时起 Proxy", 1, h.count<Effect.StartService>())
        h.serviceStarted(1, ServiceType.Vpn, 1)
        assertEquals(1, h.last<Effect.RetireService>().inst)
        assertEquals(1, h.count<Effect.StartService>())
        h.serviceDestroyed(1)
        assertEquals(ServiceType.Proxy, h.last<Effect.StartService>().type)
        h.serviceStarted(2, ServiceType.Proxy, 1)
        assertEquals(2, h.last<Effect.RunStart>().inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2)
    }

    @Test
    fun `Service 未到达时从 Proxy 切到 Vpn 旧 Proxy 销毁之前不请求授权也不起 Vpn`() {
        val h = CoreHarness(ServiceType.Proxy, autoService = false, autoDestroy = false)
        h.on(1)
        h.mode = ServiceType.Vpn
        h.on(2, rev = 1)
        assertEquals(0, h.count<Effect.RequestAuth>())
        assertEquals(1, h.count<Effect.StartService>())
        h.serviceStarted(1, ServiceType.Proxy, 1)
        assertEquals(0, h.count<Effect.RequestAuth>())
        h.serviceDestroyed(1)
        assertEquals(1, h.count<Effect.RequestAuth>())
        assertEquals(listOf(ServiceType.Proxy, ServiceType.Vpn), h.all<Effect.StartService>().map { it.type })
        h.serviceStarted(2, ServiceType.Vpn, 1)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 1)
    }

    @Test
    fun `重载回收期间切模式 回收完成后换类 不在旧类上发布 started`() {
        val h = CoreHarness(ServiceType.Vpn)
        h.connected(rev = 1)
        h.on(2, rev = 2)
        assertTrue(h.inFlight!!.soft)
        h.mode = ServiceType.Proxy
        h.on(3, rev = 2)
        h.finishTeardown() // 软回收完成：Vpn 实例上仍有 command server
        assertFalse("换类：完整回收", h.last<Effect.RunTeardown>().soft)
        h.finishTeardown() // → 退休 Vpn → onDestroy → 起 Proxy
        assertEquals(2, h.last<Effect.RunStart>().inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, desired = Desired.On)
        assertEquals(listOf(1 to ServiceType.Vpn, 2 to ServiceType.Proxy), h.startedServices)
        assertEquals(
            "Vpn 实例上从未发布过 rev=2 的 started",
            1,
            h.snapshots.count { it.status == KernelStatus.Started && it.activeConfigRevision == 2L },
        )
    }

    @Test
    fun `启动任务进行中切模式 旧类上的成功不被当作收敛`() {
        val h = CoreHarness(ServiceType.Vpn)
        h.on(1, rev = 1)
        h.mode = ServiceType.Proxy
        val m = h.mark()
        h.on(2, rev = 1)
        assertEquals("旧形态的启动已无用：打取消标", 1, h.since<Effect.CancelJob>(m).size)
        h.finishJob(JobResult.Started) // 取消标没赶上
        h.assertSnap(status = KernelStatus.Starting)
        assertTrue(h.snapshots.none { it.status == KernelStatus.Started })
        h.finishTeardown()
        assertEquals(2, h.last<Effect.RunStart>().inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 1)
        assertEquals(ServiceType.Proxy, h.startedServices.last().second)
    }

    @Test
    fun `已就绪时只改模式不改 revision 也换类 收敛看实际运行的 Service 类型`() {
        val h = CoreHarness(ServiceType.Vpn, autoDestroy = false)
        h.connected(rev = 1)
        h.mode = ServiceType.Proxy
        h.on(2, rev = 1)
        h.assertSnap(status = KernelStatus.Starting, attempt = 2)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        assertEquals(1, h.count<Effect.StartService>())
        h.serviceDestroyed(1)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 1, attempt = 2)
        assertEquals(ServiceType.Proxy, h.startedServices.last().second)
    }

    @Test
    fun `同类 off 之后马上 on 而旧实例已在退休 等销毁后用新实例`() {
        val h = CoreHarness(autoDestroy = false)
        h.connected()
        h.off(2)
        h.finishTeardown()
        assertEquals(1, h.count<Effect.RetireService>())
        h.on(3)
        assertEquals("旧实例销毁前不起新的", 1, h.count<Effect.StartService>())
        h.serviceDestroyed(1)
        assertEquals(2, h.count<Effect.StartService>())
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2)
    }

    @Test
    fun `off 后马上 on 而旧实例还没退休 复用同一个实例 不重新起 Service`() {
        val h = CoreHarness()
        h.connected()
        h.off(2)             // 回收任务在途，尚未退休
        h.on(3)
        assertEquals(0, h.count<Effect.RetireService>())
        h.finishTeardown()   // 完整回收完成
        assertEquals("复用实例", 1, h.count<Effect.StartService>())
        assertEquals(1, h.last<Effect.RunStart>().inst)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2)
    }

    // ========================================================================
    //  startId 规则（每个实例各记各的）
    // ========================================================================

    @Test
    fun `startId 按实例记录 退休用该实例自己的最大 startId`() {
        val h = CoreHarness(ServiceType.Proxy)
        h.on(1)
        h.serviceStarted(1, ServiceType.Proxy, 2)
        h.serviceStarted(1, ServiceType.Proxy, 3)
        h.finishJob(JobResult.Started)
        h.off(2)
        h.finishTeardown()
        assertEquals(3, h.last<Effect.RetireService>().maxStartId)
    }

    @Test
    fun `停止期间到达的新 startId 不会被旧的 stopSelfResult 误停`() {
        val h = CoreHarness(autoDestroy = false)
        h.connected()
        h.off(2)
        h.finishTeardown()
        assertEquals(1, h.last<Effect.RetireService>().maxStartId)
        // stopSelfResult(1) 返回 false：随后到达 startId=2（新请求）。此时 desired 仍是 off ——
        // 该启动命令是孤儿，实例再次退休（用新的 startId），但绝不会无通知地吃掉一个新请求。
        h.serviceStarted(1, ServiceType.Vpn, 2)
        assertEquals(2, h.last<Effect.RetireService>().maxStartId)
        assertEquals(2, h.count<Effect.RetireService>())
        h.on(3)
        // 新请求在该实例销毁之后才起新实例
        h.serviceDestroyed(1)
        assertEquals(2, h.count<Effect.StartService>())
    }

    @Test
    fun `孤儿 Service 在 desired off 时到达立即退休`() {
        val h = CoreHarness(autoService = false)
        h.serviceStarted(9, ServiceType.Proxy, 1)
        assertEquals(9, h.last<Effect.RetireService>().inst)
        assertEquals(KernelStatus.Stopped, h.snap.status)
    }

    // ========================================================================
    //  意外退出 / 撤销
    // ========================================================================

    @Test
    fun `Service 被系统销毁而内核在跑 视为 kernelExited 补回收`() {
        val h = CoreHarness()
        h.connected()
        h.serviceDestroyed(1)
        h.assertSnap(desired = Desired.Off)
        assertEquals(FailureCode.KernelExited, h.snap.lastFailure!!.code)
        assertEquals(1L, h.snap.lastFailure!!.seq)
        assertFalse(h.last<Effect.RunTeardown>().soft)
        h.assertSnap(status = KernelStatus.Stopping)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
        // 实例已不存在，不会再对它 stopSelfResult
        assertEquals(0, h.count<Effect.RetireService>())
    }

    @Test
    fun `系统撤销 VPN 等于 desired off source system 且不算失败`() {
        val h = CoreHarness()
        h.connected()
        h.revoked(1)
        h.assertSnap(desired = Desired.Off, source = Source.System, status = KernelStatus.Stopping)
        assertNull(h.snap.lastFailure)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
    }

    @Test
    fun `撤销事件不依赖主线程阻塞 同步返回动作而不是等待回收`() {
        val h = CoreHarness()
        h.connected()
        val s = h.revoked(1)
        assertTrue(s.effects.any { it is Effect.RunTeardown })
    }

    // ========================================================================
    //  外部来源（磁贴 / 快捷方式 / 开机 / 通知栏）
    // ========================================================================

    @Test
    fun `磁贴开启 用持久化 spec 来源标记为 tile 不推进 appliedSeq`() {
        val h = CoreHarness()
        h.external(Source.Tile, Desired.On, fallback = h.spec(9))
        h.assertSnap(desired = Desired.On, source = Source.Tile, status = KernelStatus.Starting)
        assertEquals(0L, h.snap.appliedSeq)
        assertEquals(9L, h.last<Effect.RunStart>().spec.configRevision)
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 9)
        assertEquals(h.spec(9), h.last<Effect.Persist>().spec)
    }

    @Test
    fun `外部启动失败的 failure 序号为空`() {
        val h = CoreHarness()
        h.external(Source.Boot, Desired.On, fallback = h.spec(1))
        h.finishJob(JobResult.Failed(FailureCode.StartService, "x"))
        assertNull(h.snap.lastFailure!!.seq)
        h.assertSnap(source = Source.Boot, desired = Desired.Off)
    }

    @Test
    fun `外部开启没有任何可用 spec 报 emptyConfiguration 且不拉起 Service`() {
        val h = CoreHarness()
        h.external(Source.Boot, Desired.On, fallback = null)
        assertEquals(FailureCode.EmptyConfiguration, h.snap.lastFailure!!.code)
        assertEquals(0, h.count<Effect.StartService>())
        h.assertSnap(status = KernelStatus.Stopped, desired = Desired.Off, source = Source.Boot)
    }

    @Test
    fun `通知栏停止按钮 source notification 在启动阻塞中也能停`() {
        val h = CoreHarness()
        h.on(1)
        h.external(Source.Notification, Desired.Off)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off, source = Source.Notification)
        h.finishJob(JobResult.Cancelled)
        h.finishTeardown()
        h.assertSnap(status = KernelStatus.Stopped)
    }

    @Test
    fun `冷进程外部开启 之后 Dart 请求同 revision 不重载`() {
        val h = CoreHarness()
        h.external(Source.Tile, Desired.On, fallback = h.spec(5))
        h.finishJob(JobResult.Started)
        h.on(1, rev = 5)
        assertEquals(1, h.count<Effect.RunStart>())
        h.assertSnap(status = KernelStatus.Started, source = Source.App, attempt = 1)
    }

    // ========================================================================
    //  纪元 / 序号 / 版本
    // ========================================================================

    @Test
    fun `过期序号返回 stale 且不改变任何状态 从不等待缺号`() {
        val h = CoreHarness()
        h.connected()
        h.on(5, rev = 1) // 跳号：缺号不等待
        assertEquals(5L, h.snap.appliedSeq)
        val before = h.snap
        val r = h.off(5)
        assertFalse(r.accepted)
        assertEquals(RejectReason.Stale, r.reason)
        assertEquals(5L, r.appliedSeq)
        val r2 = h.off(3)
        assertEquals(RejectReason.Stale, r2.reason)
        assertEquals(before, h.snap)
        assertEquals(KernelStatus.Started, h.snap.status)
    }

    @Test
    fun `纪元不符返回 wrongEpoch 且不改变状态`() {
        val h = CoreHarness()
        h.connected()
        val before = h.snap
        val r = h.request(9, Desired.Off, epoch = "some-other-epoch")
        assertFalse(r.accepted)
        assertEquals(RejectReason.WrongEpoch, r.reason)
        assertEquals("epoch-A", r.epoch)
        assertEquals(1L, r.appliedSeq)
        assertEquals(before, h.snap)
    }

    @Test
    fun `Dart 重建后 appliedSeq 基线保留 新请求以 appliedSeq 加一继续`() {
        val h = CoreHarness()
        h.connected(seq = 7)
        // 「Dart 引擎重建」：它读到快照 appliedSeq=7，nextSeq 从 8 开始；旧的 7 重发被拒
        assertEquals(7L, h.snap.appliedSeq)
        assertEquals(RejectReason.Stale, h.off(7).reason)
        val r = h.off(8)
        assertTrue(r.accepted)
        assertEquals(8L, h.snap.appliedSeq)
        h.assertSnap(status = KernelStatus.Stopping, desired = Desired.Off)
    }

    @Test
    fun `旧版 Pigeon 转发不带序号 不推进 appliedSeq 也不会被判过期`() {
        val h = CoreHarness()
        h.connected(seq = 4)
        val s = h.core.onRequest(null, null, Desired.Off, null, "legacy")
        h.effects += s.effects
        assertTrue(s.receipt!!.accepted)
        assertEquals(4L, h.snap.appliedSeq)
        h.assertSnap(desired = Desired.Off, source = Source.App)
    }

    @Test
    fun `version attempt 单调 一段混合序列里字段变化时 version 恰好加一`() {
        val h = CoreHarness()
        // 脚手架每一步已断言；这里跑一段覆盖面大的序列
        h.on(1, rev = 1)
        h.on(2, rev = 2)
        h.finishJob(JobResult.Started)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.ack(h.snap.attempt)
        h.off(3)
        h.on(4, rev = 3)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        val versions = h.snapshots.map { it.version }
        assertEquals(versions.sorted(), versions)
        assertEquals(versions.distinct(), versions)
        val attempts = h.snapshots.map { it.attempt }
        assertEquals(attempts.sorted(), attempts)
        assertTrue(h.snap.attempt >= 3)
    }

    // ========================================================================
    //  手选重放确认
    // ========================================================================

    @Test
    fun `acknowledgeReplay 只对当前 attempt 生效且幂等`() {
        val h = CoreHarness()
        h.connected()
        h.assertSnap(replay = true, attempt = 1)
        h.ack(99)
        h.assertSnap(replay = true)
        h.ack(1)
        h.assertSnap(replay = false)
        val v = h.snap.version
        h.ack(1)
        assertEquals(v, h.snap.version)
    }

    // ========================================================================
    //  网络切换（按句柄去重、忽略初始事件、去抖）
    // ========================================================================

    @Test
    fun `网络事件 启动期间与初始事件被吸收 同句柄重复不重载`() {
        val h = CoreHarness()
        h.on(1)
        h.network(100) // arm 之后系统补发的当前网络：启动期间
        h.finishJob(JobResult.Started)
        h.network(100) // 同一句柄再来
        assertEquals(0, h.count<Effect.RunTeardown>())
        assertFalse(h.timers.containsKey(TimerKind.NetDebounce to 0L))
        h.assertSnap(status = KernelStatus.Started, attempt = 1)
    }

    @Test
    fun `网络句柄变化 去抖之后重载一次 source 不变`() {
        val h = CoreHarness()
        h.on(1)
        h.network(100)
        h.finishJob(JobResult.Started)
        h.network(200)
        assertEquals("去抖期间不动作", KernelStatus.Started, h.snap.status)
        assertEquals(1_000L, h.effects.filterIsInstance<Effect.SetTimer>().last().delayMs)
        h.fire(TimerKind.NetDebounce)
        h.assertSnap(status = KernelStatus.Starting, attempt = 2, source = Source.App, replay = false)
        assertTrue(h.last<Effect.RunTeardown>().soft)
        h.finishTeardown()
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, attempt = 2, replay = true)
        // 新网络成为基线：再来 200 不重载
        h.network(200)
        assertEquals(1, h.count<Effect.RunTeardown>())
    }

    @Test
    fun `网络抖动回到原句柄 不重载`() {
        val h = CoreHarness()
        h.on(1)
        h.network(100)
        h.finishJob(JobResult.Started)
        h.network(200)
        h.network(100) // 回到基线
        h.fire(TimerKind.NetDebounce)
        assertEquals(0, h.count<Effect.RunTeardown>())
        h.assertSnap(status = KernelStatus.Started, attempt = 1)
    }

    @Test
    fun `网络事件在内核启动成功之后才第一次到达 作为基线而不是重载`() {
        val h = CoreHarness()
        h.connected()
        h.network(300)
        assertFalse(h.timers.containsKey(TimerKind.NetDebounce to 0L))
        h.network(300)
        assertEquals(0, h.count<Effect.RunTeardown>())
    }

    @Test
    fun `desired off 时的网络事件被忽略`() {
        val h = CoreHarness()
        h.network(1)
        h.network(2)
        assertEquals(0, h.count<Effect.StartService>())
        assertEquals(0L, h.snap.attempt)
    }

    // ========================================================================
    //  持久化
    // ========================================================================

    @Test
    fun `desired 与 spec 的变化会发出持久化动作 空操作不发`() {
        val h = CoreHarness()
        h.on(1, rev = 1)
        assertEquals(Effect.Persist(Desired.On, h.spec(1)), h.last<Effect.Persist>())
        val n = h.count<Effect.Persist>()
        h.on(2, rev = 1)
        assertEquals(n, h.count<Effect.Persist>())
        h.on(3, rev = 2)
        assertEquals(Effect.Persist(Desired.On, h.spec(2)), h.last<Effect.Persist>())
        h.off(4)
        assertEquals(Desired.Off, h.last<Effect.Persist>().desired)
    }
}
