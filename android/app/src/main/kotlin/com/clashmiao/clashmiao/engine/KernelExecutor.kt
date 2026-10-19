package com.clashmiao.clashmiao.engine

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 执行层：**唯一**的后台工作线程，按提交顺序串行执行 [KernelRuntime] 的阻塞操作（spec §3）。
 *
 * 命令层（主线程上的 [KernelCoordinator]）只负责提交与取消，永不阻塞；执行层把进度与结果
 * 通过 [postToMain] 投递回命令层。同一线程 + FIFO 队列保证「不并发」，协调器自己另外保证
 * 同一时刻至多提交一个任务，所以队列里实际上不会堆积。
 *
 * 取消是协作式的：libbox 调用不可中断，[cancel] 只置位 [ExecContext.cancelled]，
 * runtime 在步骤之间检查。
 */
class KernelExecutor(
    private val postToMain: (Runnable) -> Unit,
    private val logger: (String) -> Unit = {},
    threadName: String = "kernel-exec",
) {

    private class Task(val token: Long) : ExecContext {
        @Volatile
        override var cancelled: Boolean = false
        lateinit var onStep: (String) -> Unit
        override fun step(name: String) = onStep(name)
    }

    private val tasks = ConcurrentHashMap<Long, Task>()

    private val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, threadName).apply { isDaemon = true }
    }

    /**
     * @param onStep 在主线程回调：任务进入一个新的阻塞步骤。
     * @param onDone 在主线程回调：任务结束，恰好一次。
     */
    fun submitStart(
        token: Long,
        runtime: KernelRuntime,
        spec: LaunchSpec,
        reload: Boolean,
        onStep: (Long, String) -> Unit,
        onDone: (Long, JobResult) -> Unit,
    ) = submit(token, onStep, onDone) { ctx ->
        try {
            runtime.start(spec, reload, ctx)
        } catch (t: Throwable) {
            // runtime 约定不抛；万一抛了，也要如实上报而不是让工作线程死掉。
            logger("start threw: $t")
            JobResult.Failed(FailureCode.StartService, t.message ?: t.toString())
        }
    }

    fun submitTeardown(
        token: Long,
        runtime: KernelRuntime,
        soft: Boolean,
        onStep: (Long, String) -> Unit,
        onDone: (Long, JobResult) -> Unit,
    ) = submit(token, onStep, onDone) { ctx ->
        try {
            runtime.teardown(soft, ctx)
        } catch (t: Throwable) {
            logger("teardown threw: $t")
        }
        JobResult.TornDown
    }

    fun cancel(token: Long) {
        tasks[token]?.cancelled = true
    }

    fun shutdown() {
        worker.shutdownNow()
    }

    private fun submit(
        token: Long,
        onStep: (Long, String) -> Unit,
        onDone: (Long, JobResult) -> Unit,
        body: (ExecContext) -> JobResult,
    ) {
        val task = Task(token).also {
            it.onStep = { name -> postToMain(Runnable { onStep(token, name) }) }
        }
        tasks[token] = task
        worker.execute {
            val result = try {
                body(task)
            } catch (t: Throwable) {
                logger("job $token crashed: $t")
                JobResult.Failed(FailureCode.Unknown, t.message ?: t.toString())
            } finally {
                tasks.remove(token)
            }
            postToMain(Runnable { onDone(token, result) })
        }
    }
}
