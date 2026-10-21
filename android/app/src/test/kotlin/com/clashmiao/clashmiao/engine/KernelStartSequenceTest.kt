package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * 启动链编排（[runStartSequence]）与回收（[runTeardown]）：
 * 每个阻塞调用一返回就检查取消，不进入下一个原生步骤；回收每一步各自兜底，资源一个不漏。
 */
class KernelStartSequenceTest {

    private val spec = LaunchSpec("/cfg/1.json", "{}", "p", 1)

    private class Ctx : ExecContext {
        @Volatile override var cancelled = false
        val steps = java.util.Collections.synchronizedList(ArrayList<String>())
        override fun step(name: String) {
            steps += name
        }
    }

    /**
     * 假内核：同时实现启动步骤与回收步骤，并像生产实现一样记账——
     * 创建出来的东西一出现就记在名下（[engineHeld] / [watcherArmed] / [tunOpen]），之后全靠回收清掉。
     */
    private class FakeKernel(val ctx: Ctx) : KernelStartOps, KernelTeardownOps {
        val calls = java.util.Collections.synchronizedList(ArrayList<String>())
        var cancelAfter: String? = null
        var failAt: String? = null
        var failMessage = "boom"
        var failTeardownAt: String? = null

        @Volatile var engineHeld = false
        @Volatile var serverOpen = false
        @Volatile var engineRunning = false
        @Volatile var watcherArmed = false
        @Volatile var tunOpen = false
        @Volatile var refReleased = false
        val teardownCalls = java.util.Collections.synchronizedList(ArrayList<String>())

        private fun call(name: String) {
            calls += name
            if (failAt == name) throw IllegalStateException(failMessage)
            if (name == cancelAfter) ctx.cancelled = true
        }

        override fun bootstrap() = call("bootstrap")
        override fun createEngine() {
            if (engineHeld) return // 幂等：已有 Engine 什么都不做
            call("createEngine")
            engineHeld = true
            serverOpen = true
            refReleased = false
        }
        override fun buildConfig(spec: LaunchSpec): String = "cfg".also { call("buildConfig") }
        override fun prepareRuntime() {
            call("prepareRuntime")
            watcherArmed = true
        }
        override fun startEngine(content: String) {
            tunOpen = true // 内核启动时让宿主建 tun
            engineRunning = true
            call("startEngine")
        }

        // 回收步骤抛异常时**不**释放它名下的资源：「后续步骤仍执行」与「资源真的被释放」是两件事，
        // 不能让假实现无条件替失败的那一步把资源清掉，否则「无泄漏」断言什么也证明不了。
        private fun td(name: String, body: () -> Unit) {
            teardownCalls += name
            if (failTeardownAt == name) throw IllegalStateException("td-$name")
            body()
        }

        override fun stopEngine() = td("stopEngine") { engineRunning = false }
        override fun closeTunFd() = td("closeTun") { tunOpen = false }
        override fun closeEngine() = td("closeEngine") { serverOpen = false }
        override fun disarmNetworkWatcher() = td("disarm") { watcherArmed = false }
        override fun releaseEngineRef() = td("release") { engineHeld = false; refReleased = true }

        val leaks: List<String>
            get() = listOfNotNull(
                "engine running".takeIf { engineRunning },
                "tun fd open".takeIf { tunOpen },
                "command server open".takeIf { serverOpen },
                "network watcher armed".takeIf { watcherArmed },
                "engine ref held".takeIf { engineHeld },
            )
    }

    private val all = listOf("bootstrap", "createEngine", "buildConfig", "prepareRuntime", "startEngine")

    @Test
    fun `完整成功 依次执行全部步骤 每个阻塞步骤前都报告进度`() {
        val ctx = Ctx()
        val k = FakeKernel(ctx)
        assertEquals(JobResult.Started, runStartSequence(k, spec, reload = false, ctx = ctx))
        assertEquals(all, k.calls)
        assertEquals(
            listOf("bootstrap", "createEngine", "buildConfig", "networkWatcher", "startEngine"),
            ctx.steps.toList(),
        )
    }

    @Test
    fun `重载不再等待固定时间 步骤与首次启动完全相同`() {
        // 行为变化：旧链路重载时在 newService 与 start 之间多一步「reloadSettle」（固定等 1 s）；
        // 新内核直接再次启动，内核内部先关旧实例（U18 在真机上验证重载稳定性）。
        val ctxFresh = Ctx()
        runStartSequence(FakeKernel(ctxFresh), spec, reload = false, ctx = ctxFresh)
        val ctxReload = Ctx()
        val k = FakeKernel(ctxReload)
        assertEquals(JobResult.Started, runStartSequence(k, spec, reload = true, ctx = ctxReload))
        assertEquals(ctxFresh.steps.toList(), ctxReload.steps.toList())
        assertFalse(ctxReload.steps.contains("reloadSettle"))
    }

    @Test
    fun `任何一个检查点置位取消 后续步骤都不再执行 且回收后不遗漏资源`() {
        for ((i, step) in all.withIndex()) {
            val ctx = Ctx()
            val k = FakeKernel(ctx).also { it.cancelAfter = step }
            val result = runStartSequence(k, spec, reload = false, ctx = ctx)
            assertEquals("cancel during $step", JobResult.Cancelled, result)
            assertEquals("cancel during $step", all.take(i + 1), k.calls)
            // 协调器随后发出的完整回收：tun fd / 网络监听 / Engine 引用都不能留
            runTeardown(k, soft = false, ctx = Ctx())
            assertEquals("leaks after cancel during $step", emptyList<String>(), k.leaks)
            assertTrue("ref released after cancel during $step", !k.engineHeld)
        }
    }

    @Test
    fun `startEngine 阻塞期间收到取消 返回后立即交给回收 并释放全部资源`() {
        val ctx = Ctx()
        val k = FakeKernel(ctx)
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val ops = object : KernelStartOps by k {
            override fun startEngine(content: String) {
                k.tunOpen = true
                k.engineRunning = true
                k.calls += "startEngine"
                entered.countDown()
                release.await(30, TimeUnit.SECONDS) // 不可中断的原生启动
            }
        }
        var result: JobResult? = null
        val worker = thread { result = runStartSequence(ops, spec, reload = false, ctx = ctx) }
        assertTrue(entered.await(30, TimeUnit.SECONDS))
        ctx.cancelled = true // off 到达（只置位：协调器不会并发打断启动）
        release.countDown()
        worker.join(30_000)
        assertEquals(JobResult.Cancelled, result)
        assertEquals("startEngine", ctx.steps.last())
        // 取消之后的回收：运行中的 Engine、tun fd、网络监听、引用都清干净
        runTeardown(k, soft = false, ctx = Ctx())
        assertEquals(emptyList<String>(), k.leaks)
    }

    @Test
    fun `原生步骤失败映射到对应失败码`() {
        fun failing(at: String, message: String = "x"): JobResult {
            val ctx = Ctx()
            val k = FakeKernel(ctx).also {
                it.failAt = at
                it.failMessage = message
            }
            return runStartSequence(k, spec, reload = false, ctx = ctx)
        }
        assertEquals(FailureCode.StartCommandServer, (failing("createEngine", "command-server: x") as JobResult.Failed).code)
        assertEquals(FailureCode.EmptyConfiguration, (failing("buildConfig", "build-failed: x") as JobResult.Failed).code)
        // startEngine 的失败按内核给的前缀分类（门面在失败路径上再检查一次配置来区分）
        assertEquals(FailureCode.CreateService, (failing("startEngine", "create-service: bad config") as JobResult.Failed).code)
        assertEquals(FailureCode.StartService, (failing("startEngine", "start-service: port in use") as JobResult.Failed).code)
        assertEquals(FailureCode.StartService, (failing("startEngine", "canceled: service start interrupted") as JobResult.Failed).code)
        assertEquals(FailureCode.StartService, (failing("startEngine", "") as JobResult.Failed).code)
        val ctx = Ctx()
        assertEquals(
            FailureCode.EmptyConfiguration,
            (runStartSequence(FakeKernel(ctx), spec.copy(runtimeConfigPath = ""), false, ctx) as JobResult.Failed).code,
        )
        assertEquals(
            FailureCode.EmptyConfiguration,
            (runStartSequence(FakeKernel(Ctx()), spec.copy(optionsJson = " "), false, Ctx()) as JobResult.Failed).code,
        )
    }

    @Test
    fun `失败码分类只看前缀`() {
        assertEquals(FailureCode.CreateService, classifyStartFailure("create-service: x"))
        assertEquals(FailureCode.CreateService, classifyStartFailure("  create-service: x"))
        assertEquals(FailureCode.StartService, classifyStartFailure("start-service: x"))
        assertEquals(FailureCode.StartService, classifyStartFailure("something create-service: inside"))
        assertEquals(FailureCode.StartService, classifyStartFailure(null))
    }

    @Test
    fun `启动失败后 回收也能把已创建的资源收干净`() {
        val ctx = Ctx()
        val k = FakeKernel(ctx).also { it.failAt = "startEngine" }
        assertTrue(runStartSequence(k, spec, false, ctx) is JobResult.Failed)
        assertTrue("失败时资源仍在 runtime 名下", k.leaks.isNotEmpty())
        runTeardown(k, soft = false, ctx = Ctx())
        assertEquals(emptyList<String>(), k.leaks)
    }

    @Test
    fun `回收的每一步依次抛错 后续步骤仍执行 失败被记录 抛错那一步名下的资源确实没释放 再回收一次才收干净`() {
        val hardSteps = listOf("stopEngine", "closeTun", "closeEngine", "disarm", "release")
        // 每一步各自名下的资源：这一步抛错时，只有它名下的东西还在
        val heldBy = mapOf(
            "stopEngine" to "engine running",
            "closeTun" to "tun fd open",
            "closeEngine" to "command server open",
            "disarm" to "network watcher armed",
            "release" to "engine ref held",
        )
        for (failing in hardSteps) {
            val ctx = Ctx()
            val k = FakeKernel(ctx)
            assertEquals(JobResult.Started, runStartSequence(k, spec, false, ctx))
            k.failTeardownAt = failing
            val recorded = ArrayList<String>()
            val failures = runTeardown(k, soft = false, ctx = Ctx()) { step, _ -> recorded += step }
            // 证据一：后续步骤仍然执行了
            assertEquals("all teardown steps ran when $failing throws", hardSteps, k.teardownCalls.toList())
            assertEquals(1, failures.size)
            assertEquals(1, recorded.size)
            assertTrue("failure recorded for $failing", failures[0].second.message!!.contains("td-$failing"))
            // 证据二：别的步骤名下的资源确实释放了，抛错的那一步名下的资源确实还在（没有被假实现悄悄清掉）
            assertEquals("only the failed step's resource remains when $failing throws", listOf(heldBy.getValue(failing)), k.leaks)

            // 修好之后再回收一次（协调器的硬回收可重入）：这次资源才真的收干净
            k.failTeardownAt = null
            runTeardown(k, soft = false, ctx = Ctx())
            assertEquals("leaks after retrying teardown ($failing)", emptyList<String>(), k.leaks)

            // 之后能再次 start（新的一轮从零开始）
            k.calls.clear()
            val again = Ctx()
            assertEquals(JobResult.Started, runStartSequence(k, spec, false, again))
            assertEquals(all, k.calls)
        }
    }

    @Test
    fun `软回收只做停止与关 tun 保留 Engine 与网络监听`() {
        val ctx = Ctx()
        val k = FakeKernel(ctx)
        runStartSequence(k, spec, false, ctx)
        val rctx = Ctx()
        runTeardown(k, soft = true, ctx = rctx)
        assertEquals(listOf("stopEngine", "closeTun"), k.teardownCalls.toList())
        assertEquals(listOf("stopEngine", "closeTun"), rctx.steps.toList())
        assertTrue(k.engineHeld)
        assertTrue(k.watcherArmed)
        assertFalse(k.tunOpen)
        assertFalse(k.engineRunning)
        // 软回收之后可以直接再次启动（createEngine 幂等：不会重复创建）
        k.calls.clear()
        assertEquals(JobResult.Started, runStartSequence(k, spec, true, Ctx()))
        assertFalse(k.calls.contains("createEngine"))
    }

    @Test
    fun `软回收的某一步抛错 另一步仍执行`() {
        for (failing in listOf("stopEngine", "closeTun")) {
            val k = FakeKernel(Ctx())
            runStartSequence(k, spec, false, Ctx())
            k.failTeardownAt = failing
            val failures = runTeardown(k, soft = true, ctx = Ctx())
            assertEquals(listOf("stopEngine", "closeTun"), k.teardownCalls.toList())
            assertEquals(1, failures.size)
        }
    }

    @Test
    fun `回收幂等 重复回收没有副作用`() {
        val k = FakeKernel(Ctx())
        runStartSequence(k, spec, false, Ctx())
        runTeardown(k, false, Ctx())
        val failures = runTeardown(k, false, Ctx())
        assertTrue(failures.isEmpty())
        assertEquals(emptyList<String>(), k.leaks)
    }
}
