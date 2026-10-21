package com.clashmiao.clashmiao.engine

import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** 等默认网络的登记表：取消 / 撤销不依赖 actor 有空，也不论登记与撤销谁先到。 */
class NetworkWaitersTest {

    @Test
    fun `actor 忙时取消 登记被直接摘掉`() {
        val waiters = NetworkWaiters<String>()
        val d = CompletableDeferred<String>()
        waiters.add(d) // actor 已处理过 FetchCurrent，登记在表里；此后 actor 忙着，不会再处理任何消息
        assertEquals(1, waiters.size())

        d.cancel()
        waiters.forget(d) // 不经 actor 队列
        assertEquals("撤销不能依赖 actor 有空", 0, waiters.size())
    }

    @Test
    fun `登记消息还排在队列里时就取消 之后处理到它也不登记`() {
        val waiters = NetworkWaiters<String>()
        val d = CompletableDeferred<String>()
        d.cancel()
        waiters.forget(d) // 撤销先到：表里还没有它
        waiters.add(d) // actor 迟些才处理到 FetchCurrent
        assertEquals(0, waiters.size())
    }

    @Test
    fun `completeAll 叫醒全部并清空`() {
        val waiters = NetworkWaiters<String>()
        val a = CompletableDeferred<String>()
        val b = CompletableDeferred<String>()
        waiters.add(a)
        waiters.add(b)
        waiters.completeAll("net")
        assertTrue(a.isCompleted && b.isCompleted)
        assertEquals("net", a.getCompleted())
        assertEquals(0, waiters.size())
        // 已完成的不会被后来的 add 重新登记
        waiters.add(a)
        assertEquals(0, waiters.size())
    }

    @Test
    fun `并发的登记与取消 不论先后都不留下已取消的等待`() {
        val waiters = NetworkWaiters<String>()
        val pool = Executors.newFixedThreadPool(8)
        try {
            val n = 2000
            val done = CountDownLatch(n)
            val start = CountDownLatch(1)
            repeat(n) { i ->
                pool.execute {
                    start.await()
                    val d = CompletableDeferred<String>()
                    if (i % 2 == 0) {
                        waiters.add(d)
                        d.cancel()
                        waiters.forget(d)
                    } else {
                        // 取消方先于（排队的）登记
                        d.cancel()
                        waiters.forget(d)
                        waiters.add(d)
                    }
                    done.countDown()
                }
            }
            start.countDown()
            assertTrue(done.await(30, TimeUnit.SECONDS))
            assertEquals(0, waiters.size())
            assertFalse(waiters.size() > 0)
        } finally {
            pool.shutdownNow()
        }
    }
}
