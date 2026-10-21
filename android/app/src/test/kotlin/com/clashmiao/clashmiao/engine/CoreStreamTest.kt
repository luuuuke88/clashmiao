package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 内核流订阅的代际：disconnect 之后迟到的连接尝试不会留下 ghost client；
 * 失败时最多重试 10 次、退避线性递增。同步全靠事件（latch），30 s 只是失败兜底，没有睡眠轮询。
 */
class CoreStreamTest {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After
    fun tearDown() = scope.cancel()

    private class FakeClient(val blockConnect: Boolean = false, val failures: Int = 0) : CoreStream.Client {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val abandoned = CountDownLatch(1)
        @Volatile var connected = 0
        @Volatile var connectCalls = 0
        @Volatile var closed = 0

        override fun connect() {
            connectCalls++
            entered.countDown()
            if (blockConnect) assertTrue(release.await(30, TimeUnit.SECONDS))
            if (connectCalls <= failures) throw IllegalStateException("kernel engine is not ready")
            connected++
        }

        override fun abandon() {
            abandoned.countDown()
        }

        override fun close() {
            closed++
        }
    }

    /** 每个连接尝试任务收尾时计数；[adopted] 记录结果，供测试等「这一轮结束了」这个事件。 */
    private class Finished(n: Int = 1) {
        val latch = CountDownLatch(n)
        val results = CopyOnWriteArrayList<Boolean>()
        val callback: (Boolean) -> Unit = { results += it; latch.countDown() }
        fun await() = assertTrue("尝试任务应当结束", latch.await(30, TimeUnit.SECONDS))
    }

    @Test
    fun `正常连接后被采用 断开时关闭`() {
        val client = FakeClient()
        val finished = Finished()
        val stream = CoreStream(scope, { client }, Dispatchers.IO, backoff = {}, onAttemptFinished = finished.callback)
        stream.connect()
        finished.await()
        assertEquals(listOf(true), finished.results.toList())
        assertTrue(stream.isConnected)
        stream.disconnect()
        assertFalse(stream.isConnected)
        assertEquals(1, client.closed)
    }

    @Test
    fun `连接阻塞期间断开 返回后候选被丢弃 不会重新出现客户端`() {
        val client = FakeClient(blockConnect = true)
        val stream = CoreStream(scope, { client }, Dispatchers.IO, backoff = {})
        stream.connect()
        assertTrue(client.entered.await(30, TimeUnit.SECONDS))
        stream.disconnect()
        client.release.countDown()
        assertTrue(client.abandoned.await(30, TimeUnit.SECONDS))
        assertFalse(stream.isConnected)
        assertEquals(0, client.closed)
    }

    @Test
    fun `退避等待期间断开 连接尝试被取消 候选被丢弃`() {
        val client = FakeClient()
        val inBackoff = CountDownLatch(1)
        val stream = CoreStream(
            scope,
            { client },
            Dispatchers.IO,
            backoff = {
                inBackoff.countDown()
                delay(10_000)
            },
        )
        stream.connect()
        assertTrue("任务已创建候选并进入退避", inBackoff.await(30, TimeUnit.SECONDS))
        stream.disconnect()
        // 屏障：被取消的任务在 finally 里丢弃候选
        assertTrue(client.abandoned.await(30, TimeUnit.SECONDS))
        assertFalse(stream.isConnected)
        assertEquals(0, client.connected)
        assertEquals(0, client.closed)
    }

    @Test
    fun `连续两次 connect 只采用后一次`() {
        val first = FakeClient(blockConnect = true)
        val second = FakeClient()
        val clients = ArrayDeque(listOf(first, second))
        val finished = Finished(2)
        val stream = CoreStream(scope, { clients.removeFirst() }, Dispatchers.IO, backoff = {}, onAttemptFinished = finished.callback)
        stream.connect()
        assertTrue(first.entered.await(30, TimeUnit.SECONDS))
        stream.connect()
        assertTrue(second.entered.await(30, TimeUnit.SECONDS))
        first.release.countDown()
        assertTrue(first.abandoned.await(30, TimeUnit.SECONDS))
        finished.await()
        assertTrue(stream.isConnected)
        assertEquals("只有后一次被采用", listOf(false, true), finished.results.sortedBy { it })
        stream.disconnect()
        assertEquals(1, second.closed)
        assertEquals(0, first.closed)
    }

    @Test
    fun `一直连不上 重试 10 次后放弃 每次先退避 退避线性递增 候选被丢弃`() {
        val client = FakeClient(failures = Int.MAX_VALUE)
        val attempts = CopyOnWriteArrayList<Int>()
        val finished = Finished()
        val stream = CoreStream(
            scope,
            { client },
            Dispatchers.IO,
            backoff = { attempts += it },
            onAttemptFinished = finished.callback,
        )
        stream.connect()
        finished.await()
        assertEquals((1..10).toList(), attempts.toList())
        assertEquals("连接尝试恰好 10 次", 10, client.connectCalls)
        assertEquals(listOf(false), finished.results.toList())
        assertTrue("放弃之后候选被丢弃", client.abandoned.await(30, TimeUnit.SECONDS))
        assertFalse(stream.isConnected)
        assertEquals(0, client.closed)
    }

    @Test
    fun `前几次失败 后来成功 就被采用 不再多试`() {
        val client = FakeClient(failures = 3)
        val attempts = CopyOnWriteArrayList<Int>()
        val finished = Finished()
        val stream = CoreStream(
            scope,
            { client },
            Dispatchers.IO,
            backoff = { attempts += it },
            onAttemptFinished = finished.callback,
        )
        stream.connect()
        finished.await()
        assertEquals(listOf(1, 2, 3, 4), attempts.toList())
        assertEquals(4, client.connectCalls)
        assertEquals(listOf(true), finished.results.toList())
        assertTrue(stream.isConnected)
        stream.disconnect()
    }

    @Test
    fun `默认退避是线性的 每次递增固定步长`() {
        val delays = (1..CoreStream.MAX_ATTEMPTS).map { CoreStream.backoffMillis(it) }
        assertEquals(10, delays.size)
        assertEquals(150L, delays.first())
        assertEquals(600L, delays.last())
        val steps = delays.zipWithNext { a, b -> b - a }.toSet()
        assertEquals("相邻两次退避的差恒定", setOf(50L), steps)
    }
}
