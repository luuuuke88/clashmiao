package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.net.UnknownHostException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/**
 * 本地 DNS 调用的取消：内核放弃调用时，阻塞着的调用线程必须被叫醒，不论它卡在等默认网络，
 * 还是系统请求已经发出（系统取消后不会再回调）。同步全靠事件（latch），30 s 只是失败兜底。
 */
class DnsExchangerTest {

    private val pool = Executors.newCachedThreadPool()

    private class FakeReply : DnsReply {
        val cancelRegistered = CountDownLatch(1)

        @Volatile var cancel: (() -> Unit)? = null
        val events = CopyOnWriteArrayList<String>()

        override fun onCancel(cancel: () -> Unit) {
            this.cancel = cancel
            cancelRegistered.countDown()
        }

        override fun rawSuccess(answer: ByteArray) { events += "raw:${answer.size}" }
        override fun success(text: String) { events += "ok:$text" }
        override fun errorCode(rcode: Int) { events += "rcode:$rcode" }
        override fun errnoCode(errno: Int) { events += "errno:$errno" }
    }

    private class FakeBackend(private val networkAvailable: Boolean = true) : DnsBackend {
        val networkWaiting = CountDownLatch(1)
        val networkWaitCancelled = CountDownLatch(1)
        private val network = CompletableDeferred<Any>()
        val queried = CountDownLatch(1)
        val handleCancelled = CountDownLatch(1)

        @Volatile var rawCallback: DnsBackend.Callback<ByteArray>? = null
        @Volatile var queryCallback: DnsBackend.Callback<List<String>>? = null
        var blocking: (String) -> List<String> = { listOf("192.0.2.1") }

        override suspend fun defaultNetwork(): Any {
            if (networkAvailable) return "net"
            networkWaiting.countDown()
            try {
                return network.await()
            } catch (e: CancellationException) {
                networkWaitCancelled.countDown()
                throw e
            }
        }

        override fun raw(network: Any, message: ByteArray, callback: DnsBackend.Callback<ByteArray>): DnsCancelHandle {
            rawCallback = callback
            queried.countDown()
            return DnsCancelHandle { handleCancelled.countDown() }
        }

        override fun query(
            network: Any,
            family: String,
            domain: String,
            callback: DnsBackend.Callback<List<String>>,
        ): DnsCancelHandle {
            queryCallback = callback
            queried.countDown()
            return DnsCancelHandle { handleCancelled.countDown() }
        }

        override fun blockingLookup(network: Any, domain: String): List<String> = blocking(domain)
    }

    /** 像原生的 getAllByName 一样：中断它没有用，只有被放行才返回（30 s 兜底）。 */
    private fun uninterruptibleAwait(latch: CountDownLatch) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (latch.count > 0 && System.nanoTime() < deadline) {
            try {
                latch.await(1, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
            }
        }
    }

    private fun Future<*>.finish() {
        try {
            get(30, TimeUnit.SECONDS)
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }

    @Test
    fun `等默认网络时内核取消 调用线程被叫醒 等待登记被撤销 不回复`() {
        val backend = FakeBackend(networkAvailable = false)
        val reply = FakeReply()
        val call = pool.submit { DnsExchanger(backend).exchange(reply, byteArrayOf(1, 2)) }

        assertTrue(backend.networkWaiting.await(30, TimeUnit.SECONDS))
        // 取消登记必须在等网络之前就做好，否则这个阶段的取消没人听
        assertEquals(0L, reply.cancelRegistered.count)
        reply.cancel!!.invoke()

        call.finish()
        assertTrue("等默认网络的挂起点应被取消", backend.networkWaitCancelled.await(30, TimeUnit.SECONDS))
        assertTrue(reply.events.isEmpty())
    }

    @Test
    fun `系统请求在途时内核取消 取消系统请求并结束调用 即使系统不再回调`() {
        val backend = FakeBackend()
        val reply = FakeReply()
        val call = pool.submit { DnsExchanger(backend).exchange(reply, byteArrayOf(1)) }

        assertTrue(backend.queried.await(30, TimeUnit.SECONDS))
        reply.cancel!!.invoke() // Android 取消后撤销回调：这里不会再有 onAnswer

        call.finish()
        assertTrue("在途的系统请求应被取消", backend.handleCancelled.await(30, TimeUnit.SECONDS))
        assertTrue(reply.events.isEmpty())
    }

    @Test
    fun `lookup 的异步分支同样可被取消`() {
        val backend = FakeBackend()
        val reply = FakeReply()
        val call = pool.submit { DnsExchanger(backend).lookup(reply, async = true, family = "udp4", domain = "a.example.net") }

        assertTrue(backend.queried.await(30, TimeUnit.SECONDS))
        reply.cancel!!.invoke()

        call.finish()
        assertTrue(backend.handleCancelled.await(30, TimeUnit.SECONDS))
        assertTrue(reply.events.isEmpty())
    }

    @Test
    fun `答案从别的线程回来 调用线程被唤醒并把结果交给内核`() {
        val backend = FakeBackend()
        val reply = FakeReply()
        val call = pool.submit { DnsExchanger(backend).exchange(reply, byteArrayOf(9)) }

        assertTrue(backend.queried.await(30, TimeUnit.SECONDS))
        pool.submit { backend.rawCallback!!.onAnswer(byteArrayOf(1, 2, 3), 0) }
        call.finish()
        assertEquals(listOf("raw:3"), reply.events.toList())
    }

    @Test
    fun `非零 rcode 交回内核 errno 错误交回内核 其它异常抛出`() {
        val backend = FakeBackend()
        val reply = FakeReply()
        var call = pool.submit { DnsExchanger(backend).exchange(reply, byteArrayOf(9)) }
        assertTrue(backend.queried.await(30, TimeUnit.SECONDS))
        backend.rawCallback!!.onAnswer(byteArrayOf(), 3)
        call.finish()
        assertEquals(listOf("rcode:3"), reply.events.toList())

        val backend2 = FakeBackend()
        val reply2 = FakeReply()
        call = pool.submit { DnsExchanger(backend2).exchange(reply2, byteArrayOf(9)) }
        assertTrue(backend2.queried.await(30, TimeUnit.SECONDS))
        backend2.rawCallback!!.onError(110, RuntimeException("timeout"))
        call.finish()
        assertEquals(listOf("errno:110"), reply2.events.toList())

        val backend3 = FakeBackend()
        val reply3 = FakeReply()
        call = pool.submit { DnsExchanger(backend3).exchange(reply3, byteArrayOf(9)) }
        assertTrue(backend3.queried.await(30, TimeUnit.SECONDS))
        backend3.rawCallback!!.onError(null, IllegalStateException("boom"))
        try {
            call.finish()
            fail("非 errno 的错误应当抛给内核")
        } catch (e: IllegalStateException) {
            assertEquals("boom", e.message)
        }
        assertTrue(reply3.events.isEmpty())
    }

    @Test
    fun `阻塞解析 NXDOMAIN 回 rcode 3 成功回地址`() {
        val backend = FakeBackend()
        val reply = FakeReply()
        backend.blocking = { throw UnknownHostException(it) }
        DnsExchanger(backend).lookup(reply, async = false, family = "udp", domain = "nx.example.net")
        assertEquals(listOf("rcode:3"), reply.events.toList())

        val reply2 = FakeReply()
        backend.blocking = { listOf("192.0.2.1", "2001:db8::1") }
        DnsExchanger(backend).lookup(reply2, async = false, family = "udp", domain = "a.example.net")
        assertEquals(listOf("ok:192.0.2.1\n2001:db8::1"), reply2.events.toList())
    }

    // ---- API 26–28 的阻塞解析：Network.getAllByName 不响应中断、没有时限 ----

    @Test
    fun `阻塞解析卡住时内核取消 调用线程立即返回 工作线程之后返回也不回复`() {
        val backend = FakeBackend()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val workerDone = CountDownLatch(1)
        backend.blocking = {
            entered.countDown()
            uninterruptibleAwait(release) // 不响应中断的系统调用
            workerDone.countDown()
            listOf("192.0.2.1")
        }
        val reply = FakeReply()
        val call = pool.submit { DnsExchanger(backend).lookup(reply, async = false, family = "udp", domain = "slow.example.net") }

        assertTrue(entered.await(30, TimeUnit.SECONDS))
        reply.cancel!!.invoke()
        call.finish() // 阻塞调用还卡着，调用线程已经回来了

        release.countDown()
        assertTrue(workerDone.await(30, TimeUnit.SECONDS))
        assertTrue("取消之后不得再回复内核: ${reply.events}", reply.events.isEmpty())
    }

    @Test
    fun `阻塞解析超时 调用线程按时限返回 回 SERVFAIL 迟到的结果丢弃`() {
        val backend = FakeBackend()
        val release = CountDownLatch(1)
        val workerDone = CountDownLatch(1)
        backend.blocking = {
            uninterruptibleAwait(release)
            workerDone.countDown()
            listOf("192.0.2.1")
        }
        val reply = FakeReply()
        val exchanger = DnsExchanger(backend, blockingTimeoutMillis = 100)
        pool.submit { exchanger.lookup(reply, async = false, family = "udp", domain = "slow.example.net") }.finish()
        assertEquals(listOf("rcode:2"), reply.events.toList())

        release.countDown()
        assertTrue(workerDone.await(30, TimeUnit.SECONDS))
        assertEquals("迟到的结果不得再回复", listOf("rcode:2"), reply.events.toList())
    }

    @Test
    fun `阻塞解析的工作线程池有界 满了直接拒绝并回 SERVFAIL`() {
        val backend = FakeBackend()
        val release = CountDownLatch(1)
        val running = CountDownLatch(1)
        backend.blocking = {
            running.countDown()
            release.await(30, TimeUnit.SECONDS)
            listOf("192.0.2.1")
        }
        // 1 个工作线程、不排队：第一个请求占住它，第二个必须被拒绝而不是再起线程。
        val tiny = java.util.concurrent.ThreadPoolExecutor(1, 1, 1, TimeUnit.SECONDS, java.util.concurrent.SynchronousQueue())
        try {
            val first = FakeReply()
            val firstCall = pool.submit { DnsExchanger(backend, tiny).lookup(first, async = false, family = "udp", domain = "a.example.net") }
            assertTrue(running.await(30, TimeUnit.SECONDS))

            val second = FakeReply()
            DnsExchanger(backend, tiny).lookup(second, async = false, family = "udp", domain = "b.example.net")
            assertEquals(listOf("rcode:2"), second.events.toList())

            release.countDown()
            firstCall.finish()
            assertEquals(listOf("ok:192.0.2.1"), first.events.toList())
        } finally {
            release.countDown()
            tiny.shutdownNow()
        }
    }
}
