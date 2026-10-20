package com.clashmiao.clashmiao.engine

import android.net.DnsResolver
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import androidx.annotation.RequiresApi
import com.clashmiao.libcore.core.DNSCall
import com.clashmiao.libcore.core.LocalDNS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.InetAddress
import java.net.UnknownHostException

/**
 * 自有门面的 `LocalDNS` 实现 —— 内核触发本地 DNS 查询时（比如
 * 解析 SS / Trojan 服务端域名）走这里转到 Android 的 [DnsResolver]。
 *
 * 两条 entrypoint：
 *   - [exchange]：raw DNS message 通道，rcode 直接透传给 [DNSCall]
 *   - [lookup]：name → IP 文本结果（API < Q 才用，走 InetAddress 阻塞接口）
 *
 * 解析跑在 default network 上（[NetworkWatcher.requireCurrent]）—— VPN 自己的
 * tun 网络不能用来递归，否则 DNS 包被自己 loop 回去。
 */
object SystemDnsBridge : LocalDNS {

    private const val DNS_RCODE_NXDOMAIN = 3

    /** API 23+ 才有 raw mode；低版本 sing-box 走 [lookup]。 */
    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: DNSCall, message: ByteArray) = runBlocking {
        val net = NetworkWatcher.requireCurrent()
        suspendCancellableCoroutine { cont ->
            val cancel = CancellationSignal()
            ctx.onCancel(cancel::cancel)
            cont.invokeOnCancellation { cancel.cancel() }
            DnsResolver.getInstance().rawQuery(
                net,
                message,
                DnsResolver.FLAG_NO_RETRY,
                Dispatchers.IO.asExecutor(),
                cancel,
                object : DnsResolver.Callback<ByteArray> {
                    override fun onAnswer(answer: ByteArray, rcode: Int) {
                        if (rcode == 0) ctx.rawSuccess(answer) else ctx.errorCode(rcode)
                        cont.safeResume(Unit)
                    }

                    override fun onError(error: DnsResolver.DnsException) {
                        val cause = error.cause
                        if (cause is ErrnoException) {
                            ctx.errnoCode(cause.errno)
                            cont.safeResume(Unit)
                        } else {
                            cont.safeFail(error)
                        }
                    }
                },
            )
        }
    }

    override fun lookup(ctx: DNSCall, network: String, domain: String) = runBlocking {
        val net = NetworkWatcher.requireCurrent()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            asyncLookup(ctx, net, network, domain)
        } else {
            blockingLookup(ctx, net, domain)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private suspend fun asyncLookup(
        ctx: DNSCall,
        net: android.net.Network,
        family: String,
        domain: String,
    ) = suspendCancellableCoroutine<Unit> { cont ->
        val cancel = CancellationSignal()
        ctx.onCancel(cancel::cancel)
        cont.invokeOnCancellation { cancel.cancel() }

        val type = when {
            family.endsWith("4") -> DnsResolver.TYPE_A
            family.endsWith("6") -> DnsResolver.TYPE_AAAA
            else -> null
        }
        val callback = object : DnsResolver.Callback<Collection<InetAddress>> {
            override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) {
                if (rcode == 0) {
                    ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
                } else {
                    ctx.errorCode(rcode)
                }
                cont.safeResume(Unit)
            }

            override fun onError(error: DnsResolver.DnsException) {
                val cause = error.cause
                if (cause is ErrnoException) {
                    ctx.errnoCode(cause.errno)
                    cont.safeResume(Unit)
                } else {
                    cont.safeFail(error)
                }
            }
        }
        val resolver = DnsResolver.getInstance()
        if (type != null) {
            resolver.query(net, domain, type, DnsResolver.FLAG_NO_RETRY, Dispatchers.IO.asExecutor(), cancel, callback)
        } else {
            resolver.query(net, domain, DnsResolver.FLAG_NO_RETRY, Dispatchers.IO.asExecutor(), cancel, callback)
        }
    }

    private fun blockingLookup(ctx: DNSCall, net: android.net.Network, domain: String) {
        val addrs = try {
            net.getAllByName(domain)
        } catch (_: UnknownHostException) {
            ctx.errorCode(DNS_RCODE_NXDOMAIN)
            return
        }
        ctx.success(addrs.mapNotNull { it.hostAddress }.joinToString("\n"))
    }

    // suspend continuation 重复 resume 防御性 try/catch 包装。
    private fun <T> kotlinx.coroutines.CancellableContinuation<T>.safeResume(value: T) {
        try {
            resumeWith(Result.success(value))
        } catch (_: IllegalStateException) {
            // 已经被 cancel 或重复 resume，吞掉
        }
    }

    private fun <T> kotlinx.coroutines.CancellableContinuation<T>.safeFail(e: Throwable) {
        try {
            resumeWith(Result.failure(e))
        } catch (_: IllegalStateException) {
        }
    }
}
