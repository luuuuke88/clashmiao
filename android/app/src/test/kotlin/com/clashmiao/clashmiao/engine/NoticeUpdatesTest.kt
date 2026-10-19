package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** 动态通知启动任务的代际归属：停止 / 销毁之后迟到的任务不会重新连接统计流或注册广播。 */
class NoticeUpdatesTest {

    private class FakeOps : NoticeUpdates.Ops {
        @Volatile var gateSettings: CountDownLatch? = null
        @Volatile var gateConnect: CountDownLatch? = null
        val inSettings = CountDownLatch(1)
        val inConnect = CountDownLatch(1)
        @Volatile var dynamic = true
        @Volatile var statsConnected = false
        @Volatile var screenRegistered = false
        val log = java.util.Collections.synchronizedList(ArrayList<String>())

        override fun dynamicEnabled(): Boolean {
            inSettings.countDown()
            gateSettings?.await(5, TimeUnit.SECONDS)
            return dynamic
        }

        override fun connectStats() {
            inConnect.countDown()
            gateConnect?.await(5, TimeUnit.SECONDS)
            statsConnected = true
            log += "connect"
        }

        override fun disconnectStats() {
            statsConnected = false
            log += "disconnect"
        }

        override fun registerScreen() {
            screenRegistered = true
            log += "register"
        }

        override fun unregisterScreen() {
            screenRegistered = false
            log += "unregister"
        }
    }

    @Test
    fun `正常一代 连接统计流并注册屏幕广播 停止后全部撤掉`() {
        val ops = FakeOps()
        val u = NoticeUpdates(ops)
        u.runStart(u.begin())
        assertTrue(ops.statsConnected)
        assertTrue(ops.screenRegistered)
        u.stop()
        assertFalse(ops.statsConnected)
        assertFalse(ops.screenRegistered)
    }

    @Test
    fun `启动任务悬停时完成停止 恢复后客户端与广播都不会出现`() {
        val ops = FakeOps().also { it.gateSettings = CountDownLatch(1) }
        val u = NoticeUpdates(ops)
        val gen = u.begin()
        val job = thread { u.runStart(gen) }
        assertTrue(ops.inSettings.await(5, TimeUnit.SECONDS))
        u.stop() // off / onDestroy 先完成
        ops.gateSettings!!.countDown()
        job.join(5_000)
        assertFalse(ops.statsConnected)
        assertFalse(ops.screenRegistered)
        assertEquals(emptyList<String>(), ops.log.toList())
    }

    @Test
    fun `连接进行中到达的停止 等本代建立完成后整体撤掉 不留资源`() {
        val ops = FakeOps().also { it.gateConnect = CountDownLatch(1) }
        val u = NoticeUpdates(ops)
        val gen = u.begin()
        val job = thread { u.runStart(gen) }
        assertTrue(ops.inConnect.await(5, TimeUnit.SECONDS))
        val stopper = thread { u.stop() }
        // 停止线程确实被挡在临界区外，之后才放行连接
        val deadline = System.currentTimeMillis() + 5_000
        while (stopper.state != Thread.State.BLOCKED) {
            check(System.currentTimeMillis() < deadline) { "stopper never blocked: ${stopper.state}" }
            Thread.sleep(1)
        }
        ops.gateConnect!!.countDown()
        job.join(5_000)
        stopper.join(5_000)
        assertFalse(ops.statsConnected)
        assertFalse(ops.screenRegistered)
        assertEquals(listOf("connect", "register", "disconnect", "unregister"), ops.log.toList())
        // 之后迟到的同代任务什么也不做
        u.runStart(gen)
        assertFalse(ops.statsConnected)
        assertFalse(ops.screenRegistered)
    }

    @Test
    fun `旧代任务在新一代开始后才运行 什么也不做`() {
        val ops = FakeOps()
        val u = NoticeUpdates(ops)
        val old = u.begin()
        u.stop()
        val current = u.begin()
        u.runStart(old)
        assertFalse(ops.statsConnected)
        u.runStart(current)
        assertTrue(ops.statsConnected)
        assertTrue(ops.screenRegistered)
    }

    @Test
    fun `停止之后的屏幕亮起事件不会重新连接统计流`() {
        val ops = FakeOps()
        val u = NoticeUpdates(ops)
        u.runStart(u.begin())
        u.stop()
        u.onScreen(true)
        assertFalse(ops.statsConnected)
    }
}
