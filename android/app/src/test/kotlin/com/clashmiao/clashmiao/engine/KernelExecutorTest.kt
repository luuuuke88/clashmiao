package com.clashmiao.clashmiao.engine

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** 执行层：单线程串行、协作式取消、结果恰好一次投递回「主线程」。 */
class KernelExecutorTest {

    private val main = LinkedBlockingQueue<Runnable>()
    private val executor = KernelExecutor(postToMain = { main.put(it) })

    @After
    fun tearDown() = executor.shutdown()

    private fun pumpUntil(timeoutMs: Long = 5_000, done: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (!done()) {
            val left = deadline - System.currentTimeMillis()
            check(left > 0) { "timeout" }
            main.poll(left, TimeUnit.MILLISECONDS)?.run()
        }
    }

    private val spec = LaunchSpec("/p", "{}", "n", 1)

    private open class RecordingRuntime : KernelRuntime {
        val order = java.util.Collections.synchronizedList(ArrayList<String>())
        val threads = java.util.Collections.synchronizedSet(HashSet<String>())
        override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult {
            threads += Thread.currentThread().name
            order += "start-begin"
            ctx.step("one")
            ctx.step("two")
            order += "start-end"
            return JobResult.Started
        }

        override fun teardown(soft: Boolean, ctx: ExecContext) {
            threads += Thread.currentThread().name
            order += "teardown-soft=$soft"
        }
    }

    @Test
    fun `任务按提交顺序在同一个后台线程上串行执行 结果与进度回到主线程`() {
        val rt = RecordingRuntime()
        val steps = ArrayList<Pair<Long, String>>()
        val done = ArrayList<Pair<Long, JobResult>>()
        executor.submitStart(1, rt, spec, false, { t, n -> steps += t to n }, { t, r -> done += t to r })
        executor.submitTeardown(2, rt, true, { t, n -> steps += t to n }, { t, r -> done += t to r })
        executor.submitTeardown(3, rt, false, { t, n -> steps += t to n }, { t, r -> done += t to r })
        pumpUntil { done.size == 3 }
        assertEquals(listOf("start-begin", "start-end", "teardown-soft=true", "teardown-soft=false"), rt.order)
        assertEquals(setOf("kernel-exec"), rt.threads)
        assertEquals(listOf(1L to "one", 1L to "two"), steps)
        assertEquals(
            listOf(1L to JobResult.Started, 2L to JobResult.TornDown, 3L to JobResult.TornDown),
            done,
        )
    }

    @Test
    fun `取消是协作式的 步骤之间能看到取消标 阻塞中的调用不被打断`() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        var sawCancelled = false
        val rt = object : KernelRuntime {
            override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult {
                entered.countDown()
                release.await() // 模拟不可中断的 libbox 调用
                sawCancelled = ctx.cancelled
                return if (ctx.cancelled) JobResult.Cancelled else JobResult.Started
            }

            override fun teardown(soft: Boolean, ctx: ExecContext) = Unit
        }
        val done = ArrayList<JobResult>()
        executor.submitStart(9, rt, spec, false, { _, _ -> }, { _, r -> done += r })
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        executor.cancel(9)
        assertTrue("取消不会打断阻塞调用", done.isEmpty())
        release.countDown()
        pumpUntil { done.isNotEmpty() }
        assertTrue(sawCancelled)
        assertEquals(listOf<JobResult>(JobResult.Cancelled), done)
    }

    @Test
    fun `runtime 抛异常 被如实上报且工作线程继续可用`() {
        val boom = object : KernelRuntime {
            override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult =
                throw IllegalStateException("kaboom")

            override fun teardown(soft: Boolean, ctx: ExecContext) = throw IllegalStateException("td")
        }
        val done = ArrayList<Pair<Long, JobResult>>()
        executor.submitStart(1, boom, spec, false, { _, _ -> }, { t, r -> done += t to r })
        executor.submitTeardown(2, boom, false, { _, _ -> }, { t, r -> done += t to r })
        executor.submitStart(3, RecordingRuntime(), spec, false, { _, _ -> }, { t, r -> done += t to r })
        pumpUntil { done.size == 3 }
        val first = done[0].second as JobResult.Failed
        assertEquals("kaboom", first.message)
        assertEquals(JobResult.TornDown, done[1].second)
        assertEquals(JobResult.Started, done[2].second)
    }

    @Test
    fun `结果恰好投递一次`() {
        val rt = RecordingRuntime()
        var n = 0
        executor.submitStart(1, rt, spec, false, { _, _ -> }, { _, _ -> n++ })
        pumpUntil { n == 1 }
        Thread.sleep(50)
        while (main.isNotEmpty()) main.poll()?.run()
        assertEquals(1, n)
        assertFalse(main.isNotEmpty())
    }
}
