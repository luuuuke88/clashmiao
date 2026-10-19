package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * 命令层（[KernelCoordinator]）+ 真实执行层线程 + 假 runtime / 假平台的端到端用例：
 * 验证「核心的动作被正确翻译成线程与回调」——命令层永不阻塞、执行层串行、停止在阻塞启动中也立即生效。
 * 测试线程扮演主线程；执行层结果经 [FakePlatform.post] 排回测试线程。
 */
class KernelCoordinatorTest {

    // --- 假平台 / 假 Service / 假 runtime -------------------------------------

    private class FakePlatform(var mode: ServiceType = ServiceType.Proxy) : CoordinatorPlatform {
        val mainThread: Thread = Thread.currentThread()
        val queue = LinkedBlockingQueue<Runnable>()
        val timers = LinkedHashMap<Any, Runnable>()
        val logs = ArrayList<String>()
        lateinit var coordinator: KernelCoordinator
        val handles = ArrayList<FakeHandle>()
        val runtimes = ArrayList<FakeRuntime>()
        var nextRuntime: () -> FakeRuntime = { FakeRuntime() }
        var authAnswer: Boolean? = true // null = 不回应（模拟对话框开着）
        var startServiceError: Throwable? = null

        /** 非空时授权走真实的 [VpnConsentBroker]（与 AndroidCoordinatorPlatform 同一份逻辑）。 */
        var consent: VpnConsentBroker<String, Any>? = null

        /** 非空时新 Service 实例使用它作为运行时（而不是 [nextRuntime] 的假 runtime）。 */
        var runtimeOverride: KernelRuntime? = null

        override fun isMainThread() = Thread.currentThread() === mainThread
        override fun post(r: Runnable) {
            queue.put(r)
        }

        override fun schedule(slot: Any, delayMs: Long, r: Runnable) {
            timers[slot] = r
        }

        override fun cancel(slot: Any) {
            timers.remove(slot)
        }

        override fun requestVpnAuth(token: Long) {
            consent?.let {
                it.request(token)
                return
            }
            val a = authAnswer ?: return
            coordinator.onAuthResult(token, a)
        }

        override fun cancelVpnAuth(token: Long) {
            consent?.cancel(token)
        }

        override fun startService(type: ServiceType) {
            startServiceError?.let { throw it }
            // Android 会稍后在主线程调 onStartCommand：排队模拟。
            val rt = nextRuntime().also { runtimes += it }
            val h = FakeHandle(coordinator.nextInstanceId(), type, runtimeOverride ?: rt)
            handles += h
            post(Runnable { coordinator.onServiceStarted(h, h.nextStartId()) })
        }

        override fun currentMode() = mode
        override fun log(line: String) {
            logs += line
        }

        fun pump(timeoutMs: Long = 5_000, until: () -> Boolean) {
            val deadline = System.currentTimeMillis() + timeoutMs
            while (!until()) {
                val left = deadline - System.currentTimeMillis()
                check(left > 0) { "timeout waiting; logs=${logs.takeLast(12)}" }
                queue.poll(minOf(left, 20), TimeUnit.MILLISECONDS)?.run()
            }
        }

        fun drain() {
            while (true) (queue.poll() ?: return).run()
        }

        fun fireTimer(kind: TimerKind) {
            val slot = timers.keys.first { (it as Pair<*, *>).first == kind }
            timers.remove(slot)!!.run()
        }
    }

    private class FakeHandle(
        override val id: Int,
        override val type: ServiceType,
        override val kernelRuntime: KernelRuntime,
    ) : ServiceHandle {
        private val startIds = AtomicInteger(0)
        fun nextStartId() = startIds.incrementAndGet()
        val stopCalls = ArrayList<Int>()
        val notices = ArrayList<String>()
        override fun stopSelfResult(startId: Int): Boolean {
            stopCalls += startId
            return true
        }

        override fun noticeStarting(profileName: String) {
            notices += "starting:$profileName"
        }

        override fun noticeStarted(profileName: String) {
            notices += "started:$profileName"
        }

        override fun noticeStopUpdates() {
            notices += "stopUpdates"
        }
    }

    /** 可编程的假内核：start 可阻塞，记录资源与回收。 */
    private open class FakeRuntime(val blockStart: Boolean = false) : KernelRuntime {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val resources = AtomicInteger(0)
        val teardowns = java.util.Collections.synchronizedList(ArrayList<Boolean>())
        val concurrent = AtomicInteger(0)
        @Volatile var maxConcurrent = 0
        @Volatile var failWith: JobResult.Failed? = null

        /** 每次 start 读取的运行时配置文件路径（执行层线程写入）。 */
        val reads: MutableList<String> = java.util.Collections.synchronizedList(ArrayList<String>())

        private fun enter() {
            val n = concurrent.incrementAndGet()
            if (n > maxConcurrent) maxConcurrent = n
        }

        override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult {
            enter()
            try {
                reads += spec.runtimeConfigPath
                ctx.step("newService")
                resources.incrementAndGet() // 尚未移交的局部实例
                entered.countDown()
                if (blockStart) release.await(10, TimeUnit.SECONDS)
                failWith?.let { return it }
                if (ctx.cancelled) return JobResult.Cancelled
                return JobResult.Started
            } finally {
                concurrent.decrementAndGet()
            }
        }

        override fun teardown(soft: Boolean, ctx: ExecContext) {
            enter()
            try {
                teardowns += soft
                resources.set(0)
            } finally {
                concurrent.decrementAndGet()
            }
        }
    }

    private class MemoryKv : KeyValueStore {
        val m = HashMap<String, Any?>()

        /** 为真时所有读取抛异常（模拟存储不可读）。 */
        var failReads = false
        override fun getString(key: String): String? {
            if (failReads) error("kv unreadable")
            return m[key] as String?
        }

        override fun putString(key: String, value: String) {
            m[key] = value
        }

        override fun getBoolean(key: String, default: Boolean) = m[key] as Boolean? ?: default
    }

    // --- 装配 --------------------------------------------------------------

    private val platform = FakePlatform()
    private val kv = MemoryKv()
    private val executor = KernelExecutor(postToMain = platform::post)
    private val epoch = "epoch-shell"

    /** 手选写入记录（执行层线程上写入；条目里带写入时刻正在运行的 runtime 序号）。 */
    private val selections = java.util.Collections.synchronizedList(ArrayList<String>())
    private var selectHook: (String, String) -> Unit = { g, o -> selections += "$g/$o" }

    private val coordinator = KernelCoordinator(
        platform = platform,
        executor = executor,
        store = KernelStore(kv),
        logs = LogBuffer(10),
        epoch = epoch,
        selector = OutboundSelector { g, o -> selectHook(g, o) },
        persistIo = { it.run() }, // 同步落盘，结果仍经主线程队列回报
    ).also { platform.coordinator = it }

    @After
    fun tearDown() = executor.shutdown()

    private fun spec(rev: Long) = LaunchSpec("/cfg/$rev.json", "{}", "p$rev", rev)
    private val snap get() = coordinator.snapshot

    // --- 用例 --------------------------------------------------------------

    @Test
    fun `连接 命令层立即返回 执行层完成后快照变为 started 并发布有序快照`() {
        val seen = ArrayList<KernelSnapshot>()
        coordinator.observeSnapshot { seen += it }
        val receipt = coordinator.request(epoch, 1, Desired.On, spec(1))
        assertTrue(receipt.accepted)
        // 命令层同步返回时已经是 starting，不等执行层
        assertEquals(KernelStatus.Starting, snap.status)
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(1L, snap.appliedSeq)
        assertEquals(1L, snap.activeConfigRevision)
        assertEquals(listOf("starting:p1", "started:p1"), platform.handles.single().notices)
        // 版本严格递增且每个中间值都被发布
        val versions = seen.map { it.version }
        assertEquals(versions.sorted().distinct(), versions)
        assertEquals(KernelStatus.Stopped, seen.first().status)
        assertEquals(KernelStatus.Started, seen.last().status)
        assertEquals(setOf(epoch), seen.map { it.epoch }.toSet())
    }

    @Test
    fun `启动阻塞中收到 off 立即 stopping 局部实例在返回后被完整回收 且从不并发`() {
        platform.nextRuntime = { FakeRuntime(blockStart = true) }
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { platform.runtimes.isNotEmpty() }
        val rt = platform.runtimes.single()
        platform.pump { rt.entered.count == 0L } // 测试线程即主线程：边等边处理排队事件
        assertEquals(1, rt.resources.get())

        // off 在启动阻塞期间到达：命令层不阻塞，立即发布 stopping
        coordinator.request(epoch, 2, Desired.Off, null)
        assertEquals(KernelStatus.Stopping, snap.status)
        assertEquals(Desired.Off, snap.desired)
        assertTrue("阻塞调用返回前不并发回收", rt.teardowns.isEmpty())
        assertEquals(1, rt.resources.get())

        rt.release.countDown()
        platform.pump { snap.status == KernelStatus.Stopped }
        assertEquals("局部实例被回收", 0, rt.resources.get())
        assertEquals(listOf(false), rt.teardowns.toList())
        assertEquals("同一时刻只有一个执行层调用", 1, rt.maxConcurrent)
        // 回收之后才对该实例 stopSelfResult
        platform.pump { platform.handles.single().stopCalls.isNotEmpty() }
        assertEquals(listOf(1), platform.handles.single().stopCalls)
    }

    @Test
    fun `启动卡死超 20s 写 kernelUnresponsive 状态保持 stopping 调用返回后收尾`() {
        platform.nextRuntime = { FakeRuntime(blockStart = true) }
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { platform.runtimes.isNotEmpty() }
        val rt = platform.runtimes.single()
        platform.pump { rt.entered.count == 0L } // 测试线程即主线程：边等边处理排队事件
        platform.pump { platform.timers.keys.any { (it as Pair<*, *>).first == TimerKind.Watchdog } }
        coordinator.request(epoch, 2, Desired.Off, null)
        platform.fireTimer(TimerKind.Watchdog)
        assertEquals(FailureCode.KernelUnresponsive, snap.lastFailure!!.code)
        assertEquals(2L, snap.lastFailure!!.seq)
        assertEquals(KernelStatus.Stopping, snap.status)
        rt.release.countDown()
        platform.pump { snap.status == KernelStatus.Stopped }
        assertEquals(FailureCode.KernelUnresponsive, snap.lastFailure!!.code)
        assertEquals(0, rt.resources.get())
    }

    @Test
    fun `启动失败 写 failure 回收 退休 stopped 且持久化 desired 为 off`() {
        platform.nextRuntime = { FakeRuntime().also { it.failWith = JobResult.Failed(FailureCode.CreateService, "x") } }
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Stopped && snap.desired == Desired.Off }
        assertEquals(FailureCode.CreateService, snap.lastFailure!!.code)
        assertEquals(1L, snap.lastFailure!!.seq)
        assertEquals("off", kv.m[KernelStore.KEY_DESIRED])
        platform.pump { platform.handles.single().stopCalls.isNotEmpty() }
    }

    @Test
    fun `授权被拒 permissionDenied 且没有 Service 被拉起`() {
        platform.mode = ServiceType.Vpn
        platform.authAnswer = false
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.drain()
        assertEquals(FailureCode.PermissionDenied, snap.lastFailure!!.code)
        assertTrue(platform.handles.isEmpty())
        assertEquals(KernelStatus.Stopped, snap.status)
    }

    @Test
    fun `授权对话框开着时 off 再 on 旧授权结果不会启动新连接`() {
        platform.mode = ServiceType.Vpn
        platform.authAnswer = null
        coordinator.request(epoch, 1, Desired.On, spec(1))
        coordinator.request(epoch, 2, Desired.Off, null)
        assertEquals(KernelStatus.Stopped, snap.status)
        // 旧 token 的授权结果迟到：必须丢弃
        coordinator.onAuthResult(1L, true)
        platform.drain()
        assertTrue(platform.handles.isEmpty())
        assertEquals(Desired.Off, snap.desired)
    }

    @Test
    fun `startForegroundService 抛异常 归为 startService 失败`() {
        platform.startServiceError = IllegalStateException("background start not allowed")
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.drain()
        assertEquals(FailureCode.StartService, snap.lastFailure!!.code)
        assertEquals("background start not allowed", snap.lastFailure!!.message)
        assertEquals(KernelStatus.Stopped, snap.status)
    }

    @Test
    fun `wrongEpoch 与 stale 回执同步返回且不改变状态`() {
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        val before = snap
        assertEquals(RejectReason.WrongEpoch, coordinator.request("other", 5, Desired.Off, null).reason)
        assertEquals(RejectReason.Stale, coordinator.request(epoch, 1, Desired.Off, null).reason)
        assertEquals(before, snap)
    }

    @Test
    fun `磁贴 App 没打开 用持久化的 LaunchSpec 启动 再点一次停止`() {
        // 先让上一次会话把 spec 写进持久化，再模拟「新进程」（新的协调器共享同一个 kv）
        coordinator.request(epoch, 1, Desired.On, spec(9))
        platform.pump { snap.status == KernelStatus.Started }
        coordinator.request(epoch, 2, Desired.Off, null)
        platform.pump { snap.status == KernelStatus.Stopped }
        assertEquals(spec(9), KernelStore(kv).loadSpec())

        val platform2 = FakePlatform()
        val exec2 = KernelExecutor(postToMain = platform2::post)
        val c2 = KernelCoordinator(platform2, exec2, KernelStore(kv), LogBuffer(5), "epoch-2")
        platform2.coordinator = c2
        try {
            c2.toggleExternal(Source.Tile)
            assertEquals(Desired.On, c2.snapshot.desired)
            assertEquals(Source.Tile, c2.snapshot.source)
            platform2.pump { c2.snapshot.status == KernelStatus.Started }
            assertEquals(9L, c2.snapshot.activeConfigRevision)
            assertEquals(0L, c2.snapshot.appliedSeq)
            // 过渡期以外的再次点击：停止
            c2.toggleExternal(Source.Tile)
            assertEquals(KernelStatus.Stopping, c2.snapshot.status)
            platform2.pump { c2.snapshot.status == KernelStatus.Stopped }
        } finally {
            exec2.shutdown()
        }
    }

    @Test
    fun `开机恢复 只在持久化 desired 为 on 时才启动`() {
        coordinator.resumeFromBoot()
        assertEquals(Desired.Off, snap.desired)
        kv.m[KernelStore.KEY_DESIRED] = "on"
        kv.m[KernelStore.KEY_SPEC] = KernelStore(MemoryKv()).encode(spec(3))
        coordinator.resumeFromBoot()
        assertEquals(Source.Boot, snap.source)
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(3L, snap.activeConfigRevision)
    }

    @Test
    fun `迁移 旧键 startedByUser 为 true 的开机恢复`() {
        kv.m[KernelStore.LEGACY_STARTED_BY_USER] = true
        kv.m[KernelStore.LEGACY_ACTIVE_CONFIG_PATH] = "/old.json"
        kv.m[KernelStore.LEGACY_CONFIG_OPTIONS] = "{}"
        coordinator.resumeFromBoot()
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(0L, snap.activeConfigRevision)
    }

    @Test
    fun `通知栏停止按钮 source notification 在任何阶段都会执行`() {
        platform.nextRuntime = { FakeRuntime(blockStart = true) }
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { platform.runtimes.isNotEmpty() }
        val rt = platform.runtimes.single()
        platform.pump { rt.entered.count == 0L } // 测试线程即主线程：边等边处理排队事件
        coordinator.external(Source.Notification, Desired.Off)
        assertEquals(Source.Notification, snap.source)
        assertEquals(KernelStatus.Stopping, snap.status)
        rt.release.countDown()
        platform.pump { snap.status == KernelStatus.Stopped }
    }

    @Test
    fun `系统撤销 VPN 不阻塞 立即进入 stopping`() {
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        coordinator.onServiceRevoked(platform.handles.single())
        assertEquals(KernelStatus.Stopping, snap.status)
        assertEquals(Source.System, snap.source)
        assertNull(snap.lastFailure)
        platform.pump { snap.status == KernelStatus.Stopped }
    }

    @Test
    fun `换 Service 类 旧实例销毁之后才拉起新 Service`() {
        platform.mode = ServiceType.Vpn
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        val old = platform.handles.single()
        platform.mode = ServiceType.Proxy
        coordinator.request(epoch, 2, Desired.On, spec(2))
        platform.pump { old.stopCalls.isNotEmpty() }
        assertEquals("旧实例销毁前没有新 Service", 1, platform.handles.size)
        assertEquals(KernelStatus.Starting, snap.status)
        coordinator.onServiceDestroyed(old)
        platform.pump { snap.status == KernelStatus.Started && snap.activeConfigRevision == 2L }
        assertEquals(2, platform.handles.size)
        assertEquals(ServiceType.Proxy, platform.handles.last().type)
        assertEquals(2L, snap.attempt)
    }

    @Test
    fun `非生命周期提示分发给订阅者 取消订阅后不再收到`() {
        val got = ArrayList<Pair<AlertCode, String?>>()
        val dispose = coordinator.observeAlerts { c, m -> got += c to m }
        coordinator.emitAlert(AlertCode.RequestNotificationPermission, null)
        dispose()
        coordinator.emitAlert(AlertCode.RequestNotificationPermission, "again")
        assertEquals(listOf<Pair<AlertCode, String?>>(AlertCode.RequestNotificationPermission to null), got)
    }

    @Test
    fun `旧版转发 start 在意图已开启时是空操作 stop 与 restart 经协调器`() {
        coordinator.legacyStart(spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        val attempt = snap.attempt
        coordinator.legacyStart(spec(2)) // 已是 on：空操作
        platform.drain()
        assertEquals(attempt, snap.attempt)
        coordinator.legacyRestart(spec(3))
        platform.pump { snap.status == KernelStatus.Started && snap.activeConfigRevision == 3L }
        assertEquals(attempt + 1, snap.attempt)
        assertEquals("旧入口不推进 appliedSeq", 0L, snap.appliedSeq)
        coordinator.legacyStop()
        platform.pump { snap.status == KernelStatus.Stopped }
        coordinator.legacyRestart(spec(4)) // 已是 off：restart 无意义
        platform.drain()
        assertEquals(Desired.Off, snap.desired)
    }

    @Test
    fun `非主线程调用 request 直接拒绝而不是在错误线程改状态`() {
        var error: Throwable? = null
        val t = Thread {
            try {
                coordinator.request(epoch, 1, Desired.On, spec(1))
            } catch (e: IllegalStateException) {
                error = e
            }
        }
        t.start()
        t.join()
        assertTrue(error != null)
        assertFalse(snap.desired == Desired.On)
    }

    // --- 授权归属：真实的平台授权逻辑（审核问题 3）---------------------------

    private class ConsentScene(val platform: FakePlatform, val coordinator: KernelCoordinator) {
        @Volatile var consented = false

        /** 弹出的对话框（宿主, requestCode）。 */
        val dialogs = ArrayList<Pair<Any, Int>>()
        val host = Any()
        val broker = VpnConsentBroker<String, Any>(
            prepare = { if (consented) null else "consent-intent" },
            launch = { h, _, code -> dialogs += h to code },
            sink = { t, g, m -> coordinator.onAuthResult(t, g, m) },
        ).also {
            it.attach(host)
            platform.consent = it
        }

        fun answerLast(granted: Boolean) = broker.onResult(dialogs.last().second, granted)
    }

    @Test
    fun `授权弹窗期间 on off on 不重复弹窗 旧弹窗结果只报给旧 token 新请求关窗后自己重新检查`() {
        platform.mode = ServiceType.Vpn
        val scene = ConsentScene(platform, coordinator)
        coordinator.request(epoch, 1, Desired.On, spec(1))
        assertEquals(1, scene.dialogs.size)
        coordinator.request(epoch, 2, Desired.Off, null)
        assertEquals(KernelStatus.Stopped, snap.status)
        coordinator.request(epoch, 3, Desired.On, spec(1))
        assertEquals("对话框还开着：不重复弹窗", 1, scene.dialogs.size)
        assertEquals(KernelStatus.Starting, snap.status)

        // 用户在第一个对话框里同意：结果报给 seq=1 的 token（被核心丢弃），seq=3 重新检查后直接通过
        scene.consented = true
        scene.answerLast(true)
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(3L, snap.appliedSeq)
        assertNull(snap.lastFailure)
        assertEquals(1, platform.handles.size)
        assertEquals(1, scene.dialogs.size)
    }

    @Test
    fun `授权弹窗期间 on off on 旧弹窗被拒不会让新请求失败 新请求为自己重新弹窗`() {
        platform.mode = ServiceType.Vpn
        val scene = ConsentScene(platform, coordinator)
        coordinator.request(epoch, 1, Desired.On, spec(1))
        coordinator.request(epoch, 2, Desired.Off, null)
        coordinator.request(epoch, 3, Desired.On, spec(1))
        scene.answerLast(false) // 拒绝的是 seq=1 弹出的对话框
        platform.drain()
        assertNull("旧拒绝不终结 seq=3", snap.lastFailure)
        assertEquals(Desired.On, snap.desired)
        assertEquals("seq=3 仍需授权：为它重新弹窗", 2, scene.dialogs.size)
        assertTrue(platform.handles.isEmpty())

        scene.answerLast(false) // seq=3 自己的对话框被拒
        platform.drain()
        assertEquals(FailureCode.PermissionDenied, snap.lastFailure!!.code)
        assertEquals(3L, snap.lastFailure!!.seq)
        assertEquals(KernelStatus.Stopped, snap.status)
    }

    // --- 手选与生命周期串行（审核问题 5）----------------------------------------

    @Test
    fun `手选 校验通过后任务被挂住 期间切换 attempt 恢复后返回 stale 且不写入新实例`() {
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        val a1 = snap.attempt

        // 挂住执行层：选择任务在主线程校验通过之后、写入之前被延后
        val gate = CountDownLatch(1)
        val gateEntered = CountDownLatch(1)
        executor.runSerialized {
            gateEntered.countDown()
            gate.await(5, TimeUnit.SECONDS)
        }
        assertTrue(gateEntered.await(5, TimeUnit.SECONDS))
        var result: SelectResult? = null
        coordinator.selectOutbound("g", "x", a1) { result = it }
        assertNull("校验通过、已排队", result)

        // 切换 attempt：新 revision → 重载（回收任务排在选择任务之后）
        coordinator.request(epoch, 2, Desired.On, spec(2))
        assertEquals(KernelStatus.Starting, snap.status)
        gate.countDown()
        platform.pump { result != null && snap.status == KernelStatus.Started }
        assertTrue("旧 attempt 的写入返回 stale：$result", result is SelectResult.Stale)
        assertTrue("没有写入任何实例", selections.isEmpty())
        assertEquals(a1 + 1, snap.attempt)

        // 旧 attempt 再来：主线程直接 stale
        var late: SelectResult? = null
        coordinator.selectOutbound("g", "z", a1) { late = it }
        assertTrue(late is SelectResult.Stale)

        // 新 attempt 的选择正常写入
        var ok: SelectResult? = null
        coordinator.selectOutbound("g", "y", snap.attempt) { ok = it }
        platform.pump { ok != null }
        assertEquals(SelectResult.Ok, ok)
        assertEquals(listOf("g/y"), selections.toList())
    }

    @Test
    fun `手选写入进行中才到达的重载 回收排在写入之后 写入只落在原实例`() {
        val order = java.util.Collections.synchronizedList(ArrayList<String>())
        platform.nextRuntime = {
            object : FakeRuntime() {
                override fun teardown(soft: Boolean, ctx: ExecContext) {
                    order += "teardown"
                    super.teardown(soft, ctx)
                }
            }
        }
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        val writing = CountDownLatch(1)
        val finishWrite = CountDownLatch(1)
        selectHook = { g, o ->
            writing.countDown()
            finishWrite.await(5, TimeUnit.SECONDS)
            order += "write $g/$o"
        }
        var result: SelectResult? = null
        coordinator.selectOutbound("g", "x", snap.attempt) { result = it }
        assertTrue(writing.await(5, TimeUnit.SECONDS))
        coordinator.request(epoch, 2, Desired.On, spec(2)) // 写入进行中到达
        finishWrite.countDown()
        platform.pump { result != null && snap.status == KernelStatus.Started && snap.activeConfigRevision == 2L }
        assertEquals(SelectResult.Ok, result)
        assertEquals(listOf("write g/x", "teardown"), order.toList())
    }

    // --- start 阻塞期间取消：返回后不再绑定 command server（审核问题 7）---------

    @Test
    fun `start 阻塞期间收到 off 返回后不再 setService 直接进入完整回收`() {
        val calls = java.util.Collections.synchronizedList(ArrayList<String>())
        val inStart = CountDownLatch(1)
        val releaseStart = CountDownLatch(1)
        val ops = object : KernelStartOps {
            override fun bootstrap() { calls += "bootstrap" }
            override fun hasCommandServer() = calls.contains("commandServer")
            override fun spawnCommandServer() { calls += "commandServer" }
            override fun buildConfig(spec: LaunchSpec): String = "cfg".also { calls += "buildConfig" }
            override fun prepareRuntime() { calls += "prepareRuntime" }
            override fun newService(content: String) { calls += "newService" }
            override fun settleAfterReload(ctx: ExecContext) = true
            override fun startService() {
                calls += "start"
                inStart.countDown()
                releaseStart.await(5, TimeUnit.SECONDS)
            }
            override fun bindCommandServer() { calls += "setService" }
        }
        val runtime = object : KernelRuntime {
            override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext) =
                runStartSequence(ops, spec, reload, ctx)

            override fun teardown(soft: Boolean, ctx: ExecContext) {
                calls += "teardown(soft=$soft)"
            }
        }
        platform.runtimeOverride = runtime // 生产同款的启动链编排，原生步骤是假的
        coordinator.request(epoch, 1, Desired.On, LaunchSpec("/cfg/1.json", "{}", "p1", 1))
        platform.pump { inStart.count == 0L }
        coordinator.request(epoch, 2, Desired.Off, null)
        assertEquals(KernelStatus.Stopping, snap.status)
        releaseStart.countDown()
        platform.pump { snap.status == KernelStatus.Stopped }
        assertFalse("start 返回后不得再调用 setService：$calls", calls.contains("setService"))
        assertEquals("teardown(soft=false)", calls.last())
        assertEquals("start", calls[calls.indexOf("teardown(soft=false)") - 1])
    }

    // --- Activity 重建后迟到的授权结果（复审问题 2）-----------------------------

    private fun recreateThenNewerRequest(scene: ConsentScene): Pair<Int, Int> {
        platform.mode = ServiceType.Vpn
        coordinator.request(epoch, 1, Desired.On, spec(1))
        val oldCode = scene.dialogs.single().second
        // Activity 被销毁并重建（旧对话框的结果之后会被投递给新 Activity）
        scene.broker.detach(scene.host)
        val recreated = Any()
        scene.broker.attach(recreated)
        coordinator.request(epoch, 2, Desired.Off, null)
        coordinator.request(epoch, 3, Desired.On, spec(1))
        assertEquals("新请求在新宿主上自己检查授权、弹新对话框", 2, scene.dialogs.size)
        val (newHost, newCode) = scene.dialogs.last()
        assertTrue(newHost === recreated)
        assertTrue("每个对话框标识唯一", oldCode != newCode)
        return oldCode to newCode
    }

    @Test
    fun `Activity 重建后旧对话框的同意迟到 只报给旧 token 不会终结新请求`() {
        val scene = ConsentScene(platform, coordinator)
        val (oldCode, newCode) = recreateThenNewerRequest(scene)
        assertTrue(scene.broker.onResult(oldCode, true))
        platform.drain()
        assertTrue("旧同意不能启动新请求", platform.handles.isEmpty())
        assertEquals(Desired.On, snap.desired)
        assertEquals(KernelStatus.Starting, snap.status)
        assertNull(snap.lastFailure)
        // 新请求只按自己对话框的结果终结
        scene.consented = true
        assertTrue(scene.broker.onResult(newCode, true))
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(3L, snap.appliedSeq)
        assertNull(snap.lastFailure)
    }

    @Test
    fun `Activity 重建后旧对话框的拒绝迟到 只报给旧 token 不会让新请求失败`() {
        val scene = ConsentScene(platform, coordinator)
        val (oldCode, newCode) = recreateThenNewerRequest(scene)
        assertTrue(scene.broker.onResult(oldCode, false))
        platform.drain()
        assertNull("旧拒绝不能终结新请求", snap.lastFailure)
        assertEquals(Desired.On, snap.desired)
        assertEquals(KernelStatus.Starting, snap.status)
        scene.consented = true
        assertTrue(scene.broker.onResult(newCode, true))
        platform.pump { snap.status == KernelStatus.Started }
        assertNull(snap.lastFailure)
        // 同一结果重复投递 / 不属于授权区间的 requestCode：忽略
        assertTrue(scene.broker.onResult(oldCode, false))
        assertFalse(scene.broker.onResult(44, false))
        platform.drain()
        assertEquals(KernelStatus.Started, snap.status)
    }

    // --- 失败启动不复用半初始化的 command server（复审问题 1）--------------------

    @Test
    fun `旧启动在 StartCommandServer 失败 被同 revision 新请求接替 旧 server 关闭 新 server 重新启动 started 时 server 确实在跑`() {
        class FakeServer(val id: Int) {
            @Volatile var running = false
            @Volatile var closed = false
        }
        val servers = java.util.Collections.synchronizedList(ArrayList<FakeServer>())
        var current: FakeServer? = null
        val lock = Any()
        val spawnEntered = CountDownLatch(1)
        val spawnGate = CountDownLatch(1)
        val ops = object : KernelStartOps {
            override fun bootstrap() = Unit
            override fun hasCommandServer() = synchronized(lock) { current != null }
            override fun spawnCommandServer() {
                // 按最坏情况建模：对象先记名下再 start()（start 失败时仍留在名下）
                val s = synchronized(lock) { FakeServer(servers.size + 1).also { servers += it; current = it } }
                if (s.id == 1) {
                    spawnEntered.countDown()
                    spawnGate.await(5, TimeUnit.SECONDS)
                    throw IllegalStateException("listen failed")
                }
                s.running = true
            }
            override fun buildConfig(spec: LaunchSpec) = "cfg"
            override fun prepareRuntime() = Unit
            override fun newService(content: String) = Unit
            override fun settleAfterReload(ctx: ExecContext) = true
            override fun startService() = Unit
            override fun bindCommandServer() = Unit
        }
        platform.runtimeOverride = object : KernelRuntime {
            override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext) =
                runStartSequence(ops, spec, reload, ctx)

            override fun teardown(soft: Boolean, ctx: ExecContext) {
                if (soft) return // 软回收保留 command server
                synchronized(lock) {
                    current?.let {
                        it.running = false
                        it.closed = true
                    }
                    current = null
                }
            }
        }
        val serverRunningWhenStarted = ArrayList<Boolean>()
        coordinator.observeSnapshot {
            if (it.status == KernelStatus.Started) {
                serverRunningWhenStarted += synchronized(lock) { current?.running == true }
            }
        }

        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { spawnEntered.count == 0L }
        coordinator.request(epoch, 2, Desired.On, spec(1)) // 同 revision 的新请求接替
        spawnGate.countDown() // 旧启动的 command server start() 失败
        platform.pump { snap.status == KernelStatus.Started }

        assertEquals(2, servers.size)
        assertTrue("旧 server 已关闭", servers[0].closed)
        assertFalse(servers[0].running)
        assertTrue("新 server 重新启动", servers[1].running)
        assertFalse(servers[1].closed)
        assertEquals(listOf(true), serverRunningWhenStarted)
        assertNull("旧失败不归新请求", snap.lastFailure)
        assertEquals(2L, snap.appliedSeq)
    }

    @Test
    fun `大量未返回的弹窗加反复重建之后 最早弹窗的旧拒绝与旧同意都不能终结最新的 on`() {
        platform.mode = ServiceType.Vpn
        val scene = ConsentScene(platform, coordinator)
        var host: Any = scene.host
        var seq = 0L
        repeat(300) {
            coordinator.request(epoch, ++seq, Desired.On, spec(1))
            scene.broker.detach(host) // 弹窗后 Activity 被销毁重建，结果没回来
            host = Any()
            scene.broker.attach(host)
            coordinator.request(epoch, ++seq, Desired.Off, null)
        }
        coordinator.request(epoch, ++seq, Desired.On, spec(1))
        val newestSeq = seq
        assertEquals(301, scene.dialogs.size)
        assertEquals("标识从不重复", 301, scene.dialogs.map { it.second }.toSet().size)
        val newestCode = scene.dialogs.last().second

        scene.broker.onResult(scene.dialogs[0].second, false) // 最早的旧拒绝
        scene.broker.onResult(scene.dialogs[256].second, false) // 旧实现回绕后会撞上的位置
        scene.broker.onResult(scene.dialogs[1].second, true) // 旧同意
        platform.drain()
        assertNull("旧结果不能让最新请求失败", snap.lastFailure)
        assertEquals(Desired.On, snap.desired)
        assertEquals(KernelStatus.Starting, snap.status)
        assertTrue("旧同意不能启动最新请求", platform.handles.isEmpty())

        scene.consented = true
        scene.broker.onResult(newestCode, true)
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(newestSeq, snap.appliedSeq)
        assertNull(snap.lastFailure)
    }

    // --- 原生声明的配置文件引用（快照 retainedConfigPaths）-------------------

    private fun newProcess(
        store: KernelStore = KernelStore(kv),
    ): Triple<KernelCoordinator, FakePlatform, KernelExecutor> {
        val p2 = FakePlatform()
        val e2 = KernelExecutor(postToMain = p2::post)
        val c2 = KernelCoordinator(p2, e2, store, LogBuffer(5), "epoch-2", persistIo = { it.run() })
        p2.coordinator = c2
        return Triple(c2, p2, e2)
    }

    @Test
    fun `引用集合 持久化 spec 停止后仍在 stopped 快照里 新进程首份快照也列出 磁贴启动读的正是它`() {
        coordinator.request(epoch, 1, Desired.On, spec(9))
        platform.pump { snap.status == KernelStatus.Started }
        assertEquals(listOf("/cfg/9.json"), snap.retainedConfigPaths)

        coordinator.request(epoch, 2, Desired.Off, null)
        platform.pump { snap.status == KernelStatus.Stopped }
        assertNull(snap.activeConfigRevision)
        assertEquals("停止后原生仍持久化着这份 spec", listOf("/cfg/9.json"), snap.retainedConfigPaths)
        assertEquals("/cfg/9.json", KernelStore(kv).loadSpec()?.runtimeConfigPath)

        // 新进程（Dart 尚未发任何请求）：attach 后的首份快照就是 stopped + 持久化路径。
        val (c2, p2, e2) = newProcess()
        try {
            val seen = ArrayList<KernelSnapshot>()
            c2.observeSnapshot { seen += it }
            assertEquals(KernelStatus.Stopped, seen.first().status)
            assertNull(seen.first().activeConfigRevision)
            assertEquals(listOf("/cfg/9.json"), seen.first().retainedConfigPaths)
            // 与意图无关的事件重新推导快照之后也一样（不是只有构造时的初值带着它）。
            c2.onNetworkResolved(42)
            c2.acknowledgeReplay(99)
            p2.drain()
            assertEquals(listOf("/cfg/9.json"), c2.snapshot.retainedConfigPaths)

            // 磁贴启动：读的就是快照里声明的那份文件。
            c2.toggleExternal(Source.Tile)
            p2.pump { c2.snapshot.status == KernelStatus.Started }
            assertEquals(listOf("/cfg/9.json"), p2.runtimes.single().reads)
            assertEquals(listOf("/cfg/9.json"), c2.snapshot.retainedConfigPaths)

            c2.toggleExternal(Source.Tile)
            p2.pump { c2.snapshot.status == KernelStatus.Stopped }
            assertEquals(listOf("/cfg/9.json"), c2.snapshot.retainedConfigPaths)
            assertTrue(
                "每一份快照都带引用集合，且都包含持久化路径",
                seen.all { it.retainedConfigPaths?.contains("/cfg/9.json") == true },
            )
        } finally {
            e2.shutdown()
        }
    }

    @Test
    fun `引用集合 换配置重载后跟随持久化 旧文件不再被引用`() {
        coordinator.request(epoch, 1, Desired.On, spec(1))
        platform.pump { snap.status == KernelStatus.Started }
        coordinator.request(epoch, 2, Desired.On, spec(2))
        platform.pump { snap.status == KernelStatus.Started && snap.activeConfigRevision == 2L }
        assertEquals(listOf("/cfg/2.json"), snap.retainedConfigPaths)
        assertEquals("/cfg/2.json", KernelStore(kv).loadSpec()?.runtimeConfigPath)

        // libbox / 网络触发的重载读的是当前意图的 spec，引用集合不变。
        val attempt = snap.attempt
        coordinator.onReloadRequested(Source.System)
        platform.pump { snap.status == KernelStatus.Started && snap.attempt == attempt + 1 }
        assertEquals(
            listOf("/cfg/1.json", "/cfg/2.json", "/cfg/2.json"),
            platform.runtimes.flatMap { it.reads },
        )
        assertEquals(listOf("/cfg/2.json"), snap.retainedConfigPaths)
    }

    @Test
    fun `引用集合 同 revision 换了路径 运行中的旧路径保留到内核停止`() {
        val legacy = LaunchSpec("/cfg/runtime-config-5.json", "{}", "p", 5)
        val renamed = LaunchSpec("/cfg/runtime-5.json", "{}", "p", 5)
        coordinator.request(epoch, 1, Desired.On, legacy)
        platform.pump { snap.status == KernelStatus.Started }
        coordinator.request(epoch, 2, Desired.On, renamed)
        platform.drain()
        assertEquals(KernelStatus.Started, snap.status)
        assertEquals("同 revision 不重载", 1, platform.runtimes.flatMap { it.reads }.size)
        assertEquals(
            "运行中的内核读的是旧路径，意图 / 持久化已是新路径",
            listOf("/cfg/runtime-5.json", "/cfg/runtime-config-5.json"),
            snap.retainedConfigPaths,
        )

        coordinator.request(epoch, 3, Desired.Off, null)
        platform.pump { snap.status == KernelStatus.Stopped }
        assertEquals(listOf("/cfg/runtime-5.json"), snap.retainedConfigPaths)
    }

    /** 内存与磁盘分开的存储：getString 读内存（SharedPreferences 语义），commit 失败时磁盘不变。 */
    private class DiskKv(val disk: MutableMap<String, Any?> = HashMap()) : KeyValueStore {
        val mem = HashMap<String, Any?>(disk)
        var failCommit = false
        override fun getString(key: String) = mem[key] as String?
        override fun putString(key: String, value: String) {
            mem[key] = value
        }

        override fun getBoolean(key: String, default: Boolean) = mem[key] as Boolean? ?: default
        override fun commit(values: Map<String, String>): Boolean {
            mem.putAll(values) // 内存先更新（与 SharedPreferences 一致）
            if (failCommit) return false
            disk.clear()
            disk.putAll(mem)
            return true
        }
    }

    @Test
    fun `引用集合 内存已是 B 而磁盘仍是 A 且 commit 失败 A 全程被声明 冷进程恢复读的正是 A`() {
        val diskKv = DiskKv()
        val p1 = FakePlatform()
        val e1 = KernelExecutor(postToMain = p1::post)
        val c1 = KernelCoordinator(p1, e1, KernelStore(diskKv), LogBuffer(5), "epoch-1", persistIo = { it.run() })
        p1.coordinator = c1
        val seen = ArrayList<KernelSnapshot>()
        try {
            c1.request("epoch-1", 1, Desired.On, spec(1))
            p1.pump { c1.snapshot.status == KernelStatus.Started && c1.snapshot.retainedConfigPaths == listOf("/cfg/1.json") }
            assertEquals("/cfg/1.json", KernelStore(DiskKv(HashMap(diskKv.disk))).loadSpec()?.runtimeConfigPath)

            c1.observeSnapshot { seen += it }
            diskKv.failCommit = true
            c1.request("epoch-1", 2, Desired.On, spec(2))
            p1.pump { c1.snapshot.status == KernelStatus.Started && c1.snapshot.activeConfigRevision == 2L }
            p1.drain()
            assertEquals("内存已是 B", "/cfg/2.json", KernelStore(diskKv).loadSpec()?.runtimeConfigPath)
            assertEquals(listOf("/cfg/1.json", "/cfg/2.json"), c1.snapshot.retainedConfigPaths)
            assertTrue(p1.logs.any { it.contains("not confirmed on disk") })

            c1.request("epoch-1", 3, Desired.Off, null)
            p1.pump { c1.snapshot.status == KernelStatus.Stopped }
            p1.drain()
            assertEquals(listOf("/cfg/1.json", "/cfg/2.json"), c1.snapshot.retainedConfigPaths)
            assertTrue(
                "A 在每一份快照里都被声明",
                seen.all { it.retainedConfigPaths?.contains("/cfg/1.json") == true },
            )
        } finally {
            e1.shutdown()
        }

        // 进程被杀：只有磁盘上的内容留下来。冷进程的外部入口读的是 A。
        val (c2, p2, e2) = newProcess(KernelStore(DiskKv(HashMap(diskKv.disk))))
        try {
            assertEquals(listOf("/cfg/1.json"), c2.snapshot.retainedConfigPaths)
            c2.external(Source.Boot, Desired.On)
            p2.pump { c2.snapshot.status == KernelStatus.Started }
            assertEquals(listOf("/cfg/1.json"), p2.runtimes.single().reads)
        } finally {
            e2.shutdown()
        }
    }

    @Test
    fun `引用集合 commit 失败后的下一次确认成功 撤下旧路径`() {
        val diskKv = DiskKv()
        val p1 = FakePlatform()
        val e1 = KernelExecutor(postToMain = p1::post)
        val c1 = KernelCoordinator(p1, e1, KernelStore(diskKv), LogBuffer(5), "epoch-1", persistIo = { it.run() })
        p1.coordinator = c1
        try {
            c1.request("epoch-1", 1, Desired.On, spec(1))
            p1.pump { c1.snapshot.status == KernelStatus.Started }
            p1.drain()
            diskKv.failCommit = true
            c1.request("epoch-1", 2, Desired.On, spec(2))
            p1.pump { c1.snapshot.activeConfigRevision == 2L }
            p1.drain()
            assertEquals(listOf("/cfg/1.json", "/cfg/2.json"), c1.snapshot.retainedConfigPaths)
            diskKv.failCommit = false
            c1.request("epoch-1", 3, Desired.Off, null) // 只改 desired，但整文件写盘把 B 带了下去
            p1.pump { c1.snapshot.status == KernelStatus.Stopped }
            p1.drain()
            assertEquals("/cfg/2.json", KernelStore(DiskKv(HashMap(diskKv.disk))).loadSpec()?.runtimeConfigPath)
            assertEquals(listOf("/cfg/2.json"), c1.snapshot.retainedConfigPaths)
        } finally {
            e1.shutdown()
        }
    }

    @Test
    fun `引用集合 启动失败清掉运行 revision 后持久化路径仍在 存储为空时为空列表`() {
        assertEquals(emptyList<String>(), snap.retainedConfigPaths)
        platform.nextRuntime = {
            FakeRuntime().also { it.failWith = JobResult.Failed(FailureCode.StartService, "x") }
        }
        coordinator.request(epoch, 1, Desired.On, spec(4))
        platform.pump { snap.desired == Desired.Off && snap.status == KernelStatus.Stopped }
        assertEquals(FailureCode.StartService, snap.lastFailure?.code)
        assertNull(snap.activeConfigRevision)
        assertEquals(listOf("/cfg/4.json"), snap.retainedConfigPaths)
    }

    @Test
    fun `引用集合 存储读不出来时报未知 回读成功后恢复`() {
        kv.m[KernelStore.KEY_SPEC] = KernelStore(MemoryKv()).encode(spec(7))
        kv.failReads = true
        val (c2, p2, e2) = newProcess()
        try {
            assertNull("不知道持久化了什么：Dart 一个都不能删", c2.snapshot.retainedConfigPaths)
            kv.failReads = false
            c2.request("epoch-2", 1, Desired.On, spec(8))
            p2.pump { c2.snapshot.status == KernelStatus.Started }
            p2.drain()
            assertEquals(listOf("/cfg/8.json"), c2.snapshot.retainedConfigPaths)
        } finally {
            e2.shutdown()
        }
    }

    @Test
    fun `引用集合 迁移来的旧版持久化 spec 也被声明`() {
        kv.m[KernelStore.LEGACY_ACTIVE_CONFIG_PATH] = "/old/runtime-config-3.json"
        kv.m[KernelStore.LEGACY_CONFIG_OPTIONS] = "{}"
        val (c2, _, e2) = newProcess()
        try {
            assertEquals(listOf("/old/runtime-config-3.json"), c2.snapshot.retainedConfigPaths)
        } finally {
            e2.shutdown()
        }
    }
}
