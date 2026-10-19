package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** 启动链编排（[runStartSequence]）：每个阻塞调用一返回就检查取消，不进入下一个原生步骤。 */
class KernelStartSequenceTest {

    private val spec = LaunchSpec("/cfg/1.json", "{}", "p", 1)

    private class Ctx : ExecContext {
        @Volatile override var cancelled = false
        val steps = java.util.Collections.synchronizedList(ArrayList<String>())
        override fun step(name: String) {
            steps += name
        }
    }

    /** 记录调用顺序；[cancelAfter] 指定的步骤执行时置位取消标（模拟 off 在该调用阻塞期间到达）。 */
    private class Ops(val ctx: Ctx, val cancelAfter: String? = null) : KernelStartOps {
        val calls = ArrayList<String>()
        private fun call(name: String) {
            calls += name
            if (name == cancelAfter) ctx.cancelled = true
        }

        override fun bootstrap() = call("bootstrap")
        override fun hasCommandServer() = false
        override fun spawnCommandServer() = call("commandServer")
        override fun buildConfig(spec: LaunchSpec): String = "cfg".also { call("buildConfig") }
        override fun prepareRuntime() = call("prepareRuntime")
        override fun newService(content: String) = call("newService")
        override fun settleAfterReload(ctx: ExecContext): Boolean {
            call("settle")
            return !ctx.cancelled
        }

        override fun startService() = call("start")
        override fun bindCommandServer() = call("setService")
    }

    private val all = listOf(
        "bootstrap", "commandServer", "buildConfig", "prepareRuntime", "newService", "settle", "start", "setService",
    )

    @Test
    fun `完整成功 依次执行全部步骤 每个阻塞步骤前都报告进度`() {
        val ctx = Ctx()
        val ops = Ops(ctx)
        assertEquals(JobResult.Started, runStartSequence(ops, spec, reload = true, ctx = ctx))
        assertEquals(all, ops.calls)
        assertEquals(
            listOf("bootstrap", "commandServer", "buildConfig", "networkWatcher", "newService", "start", "bindCommandServer"),
            ctx.steps.toList(),
        )
    }

    @Test
    fun `任何一个阻塞调用期间被取消 返回后都不再进入下一个原生步骤`() {
        for ((i, step) in all.withIndex()) {
            val ctx = Ctx()
            val ops = Ops(ctx, cancelAfter = step)
            val result = runStartSequence(ops, spec, reload = true, ctx = ctx)
            if (step == "setService") {
                assertEquals(JobResult.Cancelled, result)
                assertEquals(all, ops.calls)
            } else {
                assertEquals("cancel during $step", JobResult.Cancelled, result)
                assertEquals("cancel during $step", all.take(i + 1), ops.calls)
            }
        }
    }

    @Test
    fun `start 阻塞期间收到取消 返回后不调用 setService`() {
        val ctx = Ctx()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = java.util.Collections.synchronizedList(ArrayList<String>())
        val ops = object : KernelStartOps by Ops(ctx) {
            override fun startService() {
                calls += "start"
                entered.countDown()
                release.await(5, TimeUnit.SECONDS) // 不可中断的 libbox start
            }

            override fun bindCommandServer() {
                calls += "setService"
            }
        }
        var result: JobResult? = null
        val worker = thread { result = runStartSequence(ops, spec, reload = false, ctx = ctx) }
        assertEquals(true, entered.await(5, TimeUnit.SECONDS))
        ctx.cancelled = true // off 到达
        release.countDown()
        worker.join(5_000)
        assertEquals(JobResult.Cancelled, result)
        assertFalse(calls.contains("setService"))
        assertEquals("start", ctx.steps.last())
    }

    @Test
    fun `原生步骤失败映射到对应失败码`() {
        fun failing(at: String): JobResult {
            val ctx = Ctx()
            val ops = object : KernelStartOps by Ops(ctx) {
                override fun spawnCommandServer() = if (at == "commandServer") error("cs") else Unit
                override fun buildConfig(spec: LaunchSpec): String = if (at == "buildConfig") error("cfg") else "x"
                override fun newService(content: String) = if (at == "newService") error("ns") else Unit
                override fun startService() = if (at == "start") error("st") else Unit
            }
            return runStartSequence(ops, spec, reload = false, ctx = ctx)
        }
        assertEquals(FailureCode.StartCommandServer, (failing("commandServer") as JobResult.Failed).code)
        assertEquals(FailureCode.EmptyConfiguration, (failing("buildConfig") as JobResult.Failed).code)
        assertEquals(FailureCode.CreateService, (failing("newService") as JobResult.Failed).code)
        assertEquals(FailureCode.StartService, (failing("start") as JobResult.Failed).code)
        val ctx = Ctx()
        assertEquals(
            FailureCode.EmptyConfiguration,
            (runStartSequence(Ops(ctx), spec.copy(runtimeConfigPath = ""), false, ctx) as JobResult.Failed).code,
        )
    }
}
