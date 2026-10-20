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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 内核流订阅的代际：disconnect 之后迟到的连接尝试不会留下 ghost client。 */
class CoreStreamTest {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @After
    fun tearDown() = scope.cancel()

    private class FakeClient(val blockConnect: Boolean = false) : CoreStream.Client {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val abandoned = CountDownLatch(1)
        @Volatile var connected = 0
        @Volatile var closed = 0

        override fun connect() {
            entered.countDown()
            if (blockConnect) release.await(5, TimeUnit.SECONDS)
            connected++
        }

        override fun abandon() {
            abandoned.countDown()
        }

        override fun close() {
            closed++
        }
    }

    private fun waitUntil(cond: () -> Boolean) {
        val deadline = System.currentTimeMillis() + 5_000
        while (!cond()) {
            check(System.currentTimeMillis() < deadline) { "timeout" }
            Thread.sleep(5)
        }
    }

    @Test
    fun `正常连接后被采用 断开时关闭`() {
        val client = FakeClient()
        val stream = CoreStream(scope, { client }, Dispatchers.IO, backoff = {})
        stream.connect()
        waitUntil { stream.isConnected }
        stream.disconnect()
        assertFalse(stream.isConnected)
        assertEquals(1, client.closed)
    }

    @Test
    fun `连接阻塞期间断开 返回后候选被丢弃 不会重新出现客户端`() {
        val client = FakeClient(blockConnect = true)
        val stream = CoreStream(scope, { client }, Dispatchers.IO, backoff = {})
        stream.connect()
        assertTrue(client.entered.await(5, TimeUnit.SECONDS))
        stream.disconnect()
        client.release.countDown()
        assertTrue(client.abandoned.await(5, TimeUnit.SECONDS))
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
        assertTrue("任务已创建候选并进入退避", inBackoff.await(5, TimeUnit.SECONDS))
        stream.disconnect()
        // 屏障：被取消的任务在 finally 里丢弃候选
        assertTrue(client.abandoned.await(5, TimeUnit.SECONDS))
        assertFalse(stream.isConnected)
        assertEquals(0, client.connected)
        assertEquals(0, client.closed)
    }

    @Test
    fun `连续两次 connect 只采用后一次`() {
        val first = FakeClient(blockConnect = true)
        val second = FakeClient()
        val clients = ArrayDeque(listOf(first, second))
        val stream = CoreStream(scope, { clients.removeFirst() }, Dispatchers.IO, backoff = {})
        stream.connect()
        assertTrue(first.entered.await(5, TimeUnit.SECONDS))
        stream.connect()
        waitUntil { stream.isConnected }
        first.release.countDown()
        assertTrue(first.abandoned.await(5, TimeUnit.SECONDS))
        assertTrue(stream.isConnected)
        stream.disconnect()
        assertEquals(1, second.closed)
        assertEquals(0, first.closed)
    }
}
