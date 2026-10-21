package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.net.UnknownHostException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** 内核给一次本地 DNS 调用的回复通道（生产是 `DNSCall`，测试是假的）。 */
internal interface DnsReply {
    /** 登记「内核放弃这次调用」的回调：内核可能在任何阶段（等默认网络、系统请求在途）调它。 */
    fun onCancel(cancel: () -> Unit)
    fun rawSuccess(answer: ByteArray)
    fun success(text: String)
    fun errorCode(rcode: Int)
    fun errnoCode(errno: Int)
}

/** 一次在途系统 DNS 请求的取消句柄；取消之后系统保证不再回调。 */
internal fun interface DnsCancelHandle {
    fun cancel()
}

/** 系统解析器（生产是 [android.net.DnsResolver] + [NetworkWatcher]；测试用假的）。回调至多触发一次。 */
internal interface DnsBackend {
    interface Callback<T> {
        fun onAnswer(answer: T, rcode: Int)

        /** [errno] 非空表示底层 errno 错误（交回内核）；为空时 [error] 是需要抛出的异常。 */
        fun onError(errno: Int?, error: Throwable)
    }

    /** 等待默认网络；协程被取消时必须撤销等待（不能留下永远等不到的登记）。 */
    suspend fun defaultNetwork(): Any

    fun raw(network: Any, message: ByteArray, callback: Callback<ByteArray>): DnsCancelHandle

    fun query(network: Any, family: String, domain: String, callback: Callback<List<String>>): DnsCancelHandle

    /** API < Q 的阻塞解析；抛 [UnknownHostException] 表示 NXDOMAIN。 */
    fun blockingLookup(network: Any, domain: String): List<String>
}

/**
 * 本地 DNS 一次调用的完整流程：等默认网络 → 发系统请求 → 把结果交回内核。
 *
 * 这条调用跑在内核的调用线程上（阻塞），所以**内核取消必须能叫醒它**：取消回调在最开始登记，
 * 触发时取消整个协程——不论它卡在等默认网络，还是系统请求已经发出（系统取消后会撤销回调，
 * 如果只取消系统请求而不结束协程，这个线程会永远等一个不会来的回调，连同 JNI 引用一起泄漏）。
 */
internal class DnsExchanger(
    private val backend: DnsBackend,
    /** 旧版 Android（API < Q）阻塞解析的工作线程池：有界，见 [lookup]。 */
    private val blockingExecutor: ExecutorService = defaultBlockingExecutor,
    /** 单次阻塞解析的时限；到时放弃等待（工作线程仍在后台跑完，结果丢弃）。 */
    private val blockingTimeoutMillis: Long = DEFAULT_BLOCKING_TIMEOUT_MS,
) {

    fun exchange(rawReply: DnsReply, message: ByteArray) = runCancellable(rawReply) { reply ->
        val net = backend.defaultNetwork()
        suspendCancellableCoroutine<Unit> { cont ->
            val handle = backend.raw(net, message, object : DnsBackend.Callback<ByteArray> {
                override fun onAnswer(answer: ByteArray, rcode: Int) {
                    if (rcode == 0) reply.rawSuccess(answer) else reply.errorCode(rcode)
                    cont.safeResume()
                }

                override fun onError(errno: Int?, error: Throwable) = failOrErrno(cont, reply, errno, error)
            })
            cont.invokeOnCancellation { handle.cancel() }
        }
    }

    /** [async] 为真走异步系统接口（API ≥ Q），否则阻塞解析。 */
    fun lookup(rawReply: DnsReply, async: Boolean, family: String, domain: String) =
        runCancellable(rawReply) { reply ->
        val net = backend.defaultNetwork()
        if (!async) {
            // API 26–28 只有同步的 Network.getAllByName，它不响应中断、也没有时限。
            // 所以放到有界的工作线程上跑，调用线程只等「结果 / 取消 / 时限」三者先到的一个：
            // 取消或超时时调用线程立刻返回（JNI 引用随之释放），工作线程在后台自行结束，结果丢弃，不再回复。
            when (val r = lookupBlocking(net, domain)) {
                is BlockingLookup.Answer -> reply.success(r.addresses.joinToString("\n"))
                BlockingLookup.NxDomain -> reply.errorCode(DNS_RCODE_NXDOMAIN)
                BlockingLookup.Unavailable -> reply.errorCode(DNS_RCODE_SERVFAIL)
                is BlockingLookup.Failed -> throw r.error
            }
            return@runCancellable
        }
        suspendCancellableCoroutine<Unit> { cont ->
            val handle = backend.query(net, family, domain, object : DnsBackend.Callback<List<String>> {
                override fun onAnswer(answer: List<String>, rcode: Int) {
                    if (rcode == 0) reply.success(answer.joinToString("\n")) else reply.errorCode(rcode)
                    cont.safeResume()
                }

                override fun onError(errno: Int?, error: Throwable) = failOrErrno(cont, reply, errno, error)
            })
            cont.invokeOnCancellation { handle.cancel() }
        }
    }

    private sealed interface BlockingLookup {
        class Answer(val addresses: List<String>) : BlockingLookup
        data object NxDomain : BlockingLookup

        /** 超时或工作线程池已满：当作解析失败回给内核。 */
        data object Unavailable : BlockingLookup
        class Failed(val error: Throwable) : BlockingLookup
    }

    private suspend fun lookupBlocking(net: Any, domain: String): BlockingLookup =
        withTimeoutOrNull(blockingTimeoutMillis) {
            suspendCancellableCoroutine<BlockingLookup> { cont ->
                val future = try {
                    blockingExecutor.submit {
                        val result = try {
                            BlockingLookup.Answer(backend.blockingLookup(net, domain))
                        } catch (_: UnknownHostException) {
                            BlockingLookup.NxDomain
                        } catch (e: Throwable) {
                            BlockingLookup.Failed(e)
                        }
                        // 协程已取消 / 超时则这次 resume 被忽略：迟到的结果没有人接收，更不会回复内核。
                        cont.resumeWith(Result.success(result))
                    }
                } catch (_: RejectedExecutionException) {
                    cont.resumeWith(Result.success(BlockingLookup.Unavailable))
                    return@suspendCancellableCoroutine
                }
                cont.invokeOnCancellation { future.cancel(true) }
            }
        } ?: BlockingLookup.Unavailable

    private fun runCancellable(reply: DnsReply, block: suspend CoroutineScope.(DnsReply) -> Unit) {
        // 回复闸门：内核取消之后不再向它回复（取消回调与回复竞争同一个状态位，先到先得）。
        val guarded = OnceReply(reply)
        try {
            runBlocking {
                val job = coroutineContext[Job]!!
                reply.onCancel {
                    guarded.markCancelled()
                    job.cancel(CancellationException("dns call cancelled by the core"))
                }
                block(guarded)
            }
        } catch (_: CancellationException) {
            // 内核主动取消：它不再等结果，没有东西要回复，也不能把取消当成错误抛回内核。
        }
    }

    private fun failOrErrno(
        cont: kotlinx.coroutines.CancellableContinuation<Unit>,
        reply: DnsReply,
        errno: Int?,
        error: Throwable,
    ) {
        if (errno != null) {
            reply.errnoCode(errno)
            cont.safeResume()
        } else {
            cont.safeFail(error)
        }
    }

    // continuation 可能已被取消，或系统重复回调：吞掉重复的 resume。
    private fun kotlinx.coroutines.CancellableContinuation<Unit>.safeResume() {
        try {
            resumeWith(Result.success(Unit))
        } catch (_: IllegalStateException) {
        }
    }

    private fun kotlinx.coroutines.CancellableContinuation<Unit>.safeFail(e: Throwable) {
        try {
            resumeWith(Result.failure(e))
        } catch (_: IllegalStateException) {
        }
    }

    /** 至多回复一次，且内核取消之后一次也不回复。 */
    private class OnceReply(private val inner: DnsReply) : DnsReply {
        private val state = AtomicInteger(OPEN)

        fun markCancelled() {
            state.compareAndSet(OPEN, CANCELLED)
        }

        private inline fun once(send: () -> Unit) {
            if (state.compareAndSet(OPEN, REPLIED)) send()
        }

        override fun onCancel(cancel: () -> Unit) = inner.onCancel(cancel)
        override fun rawSuccess(answer: ByteArray) = once { inner.rawSuccess(answer) }
        override fun success(text: String) = once { inner.success(text) }
        override fun errorCode(rcode: Int) = once { inner.errorCode(rcode) }
        override fun errnoCode(errno: Int) = once { inner.errnoCode(errno) }

        private companion object {
            const val OPEN = 0
            const val REPLIED = 1
            const val CANCELLED = 2
        }
    }

    companion object {
        private const val DNS_RCODE_NXDOMAIN = 3
        private const val DNS_RCODE_SERVFAIL = 2

        /** 单次阻塞解析的时限（系统自己的解析超时通常更长，这里取能容忍的上界）。 */
        const val DEFAULT_BLOCKING_TIMEOUT_MS = 10_000L

        /** 有界：最多 8 个工作线程、32 个排队；再多就直接拒绝（回 SERVFAIL），不无限堆线程。空闲 30 s 回收。 */
        val defaultBlockingExecutor: ExecutorService = ThreadPoolExecutor(
            8, 8, 30L, TimeUnit.SECONDS, ArrayBlockingQueue(32),
        ) { r -> Thread(r, "dns-blocking-lookup").apply { isDaemon = true } }.apply { allowCoreThreadTimeOut(true) }
    }
}
