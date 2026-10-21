package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.UnknownHostException

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
internal class DnsExchanger(private val backend: DnsBackend) {

    fun exchange(reply: DnsReply, message: ByteArray) = runCancellable(reply) {
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
    fun lookup(reply: DnsReply, async: Boolean, family: String, domain: String) = runCancellable(reply) {
        val net = backend.defaultNetwork()
        if (!async) {
            val addrs = try {
                backend.blockingLookup(net, domain)
            } catch (_: UnknownHostException) {
                reply.errorCode(DNS_RCODE_NXDOMAIN)
                return@runCancellable
            }
            reply.success(addrs.joinToString("\n"))
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

    private fun runCancellable(reply: DnsReply, block: suspend CoroutineScope.() -> Unit) {
        try {
            runBlocking {
                val job = coroutineContext[Job]!!
                reply.onCancel { job.cancel(CancellationException("dns call cancelled by the core")) }
                block()
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

    private companion object {
        const val DNS_RCODE_NXDOMAIN = 3
    }
}
