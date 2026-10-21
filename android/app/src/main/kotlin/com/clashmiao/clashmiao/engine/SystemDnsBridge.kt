package com.clashmiao.clashmiao.engine

import android.net.DnsResolver
import android.net.Network
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import androidx.annotation.RequiresApi
import com.clashmiao.libcore.core.DNSCall
import com.clashmiao.libcore.core.LocalDNS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import java.net.InetAddress

/**
 * 自有门面的 `LocalDNS` 实现 —— 内核触发本地 DNS 查询时（比如
 * 解析 SS / Trojan 服务端域名）走这里转到 Android 的 [DnsResolver]。
 *
 * 两条 entrypoint：
 *   - [exchange]：raw DNS message 通道，rcode 直接透传给 [DNSCall]
 *   - [lookup]：name → IP 文本结果（API < Q 才用，走 InetAddress 阻塞接口）
 *
 * 解析跑在 default network 上（[NetworkWatcher.requireCurrent]）—— VPN 自己的
 * tun 网络不能用来递归，否则 DNS 包被自己 loop 回去。流程与取消语义在 [DnsExchanger]
 * （可脱离 Android 测试）；这里只是把它接到真实的 DNSCall / DnsResolver 上。
 */
object SystemDnsBridge : LocalDNS {

    private val exchanger = DnsExchanger(AndroidDnsBackend)

    /** API 23+ 才有 raw mode；低版本 sing-box 走 [lookup]。 */
    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: DNSCall, message: ByteArray) {
        exchanger.exchange(CallReply(ctx), message)
    }

    override fun lookup(ctx: DNSCall, network: String, domain: String) {
        exchanger.lookup(CallReply(ctx), Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q, network, domain)
    }

    private class CallReply(private val ctx: DNSCall) : DnsReply {
        override fun onCancel(cancel: () -> Unit) = ctx.onCancel { cancel() }
        override fun rawSuccess(answer: ByteArray) = ctx.rawSuccess(answer)
        override fun success(text: String) = ctx.success(text)
        override fun errorCode(rcode: Int) = ctx.errorCode(rcode)
        override fun errnoCode(errno: Int) = ctx.errnoCode(errno)
    }

    private object AndroidDnsBackend : DnsBackend {
        override suspend fun defaultNetwork(): Any = NetworkWatcher.requireCurrent()

        @RequiresApi(Build.VERSION_CODES.Q)
        override fun raw(network: Any, message: ByteArray, callback: DnsBackend.Callback<ByteArray>): DnsCancelHandle {
            val cancel = CancellationSignal()
            DnsResolver.getInstance().rawQuery(
                network as Network,
                message,
                DnsResolver.FLAG_NO_RETRY,
                Dispatchers.IO.asExecutor(),
                cancel,
                object : DnsResolver.Callback<ByteArray> {
                    override fun onAnswer(answer: ByteArray, rcode: Int) = callback.onAnswer(answer, rcode)
                    override fun onError(error: DnsResolver.DnsException) =
                        callback.onError((error.cause as? ErrnoException)?.errno, error)
                },
            )
            return DnsCancelHandle { cancel.cancel() }
        }

        @RequiresApi(Build.VERSION_CODES.Q)
        override fun query(
            network: Any,
            family: String,
            domain: String,
            callback: DnsBackend.Callback<List<String>>,
        ): DnsCancelHandle {
            val cancel = CancellationSignal()
            val type = when {
                family.endsWith("4") -> DnsResolver.TYPE_A
                family.endsWith("6") -> DnsResolver.TYPE_AAAA
                else -> null
            }
            val cb = object : DnsResolver.Callback<Collection<InetAddress>> {
                override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) =
                    callback.onAnswer(answer.mapNotNull { it.hostAddress }, rcode)

                override fun onError(error: DnsResolver.DnsException) =
                    callback.onError((error.cause as? ErrnoException)?.errno, error)
            }
            val resolver = DnsResolver.getInstance()
            val executor = Dispatchers.IO.asExecutor()
            if (type != null) {
                resolver.query(network as Network, domain, type, DnsResolver.FLAG_NO_RETRY, executor, cancel, cb)
            } else {
                resolver.query(network as Network, domain, DnsResolver.FLAG_NO_RETRY, executor, cancel, cb)
            }
            return DnsCancelHandle { cancel.cancel() }
        }

        override fun blockingLookup(network: Any, domain: String): List<String> =
            (network as Network).getAllByName(domain).mapNotNull { it.hostAddress }
    }
}
