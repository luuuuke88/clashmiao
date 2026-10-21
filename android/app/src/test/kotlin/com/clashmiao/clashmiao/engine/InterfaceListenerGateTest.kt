package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** 接口监听的代次与排空屏障：换监听返回之后，旧监听不会再被调用，也没有在途的旧回调。事件同步，30 s 只作兜底。 */
class InterfaceListenerGateTest {

    private val pool = Executors.newCachedThreadPool()

    private class Listener(val name: String) {
        val calls = CopyOnWriteArrayList<String>()
    }

    private fun spinUntil(what: String, cond: () -> Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
        while (!cond()) {
            check(System.nanoTime() < deadline) { "timeout waiting for $what" }
            Thread.onSpinWait()
        }
    }

    @Test
    fun `换监听要等在途的旧回调返回 之后旧监听不再被调用`() {
        val gate = InterfaceListenerGate<Listener>()
        val old = Listener("old")
        val new = Listener("new")
        gate.attach(old)

        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val seq = AtomicInteger()
        val oldExit = AtomicInteger()
        val attachReturned = AtomicInteger()

        val inFlight = pool.submit {
            gate.dispatch { l ->
                l.calls += "start"
                entered.countDown()
                release.await(30, TimeUnit.SECONDS)
                l.calls += "end"
                // 在回调末尾、仍计入在途数量时记录：dispatch 返回之后才记会让「换监听返回」抢在前面，是测试自己的调度窗口。
                oldExit.set(seq.incrementAndGet())
            }
        }
        assertTrue(entered.await(30, TimeUnit.SECONDS))

        val gen0 = gate.generation()
        val switching = pool.submit {
            gate.attach(new)
            attachReturned.set(seq.incrementAndGet())
        }
        spinUntil("attach to revoke the old listener") { gate.generation() != gen0 }
        // 旧监听已被撤下：此刻再来的派发拿不到它
        assertFalse(gate.dispatch { it.calls += "late" })
        release.countDown()

        inFlight.get(30, TimeUnit.SECONDS)
        switching.get(30, TimeUnit.SECONDS)
        assertTrue("attach 必须在旧回调返回之后才返回", oldExit.get() < attachReturned.get())
        assertEquals(listOf("start", "end"), old.calls.toList())

        // 新监听生效
        assertTrue(gate.dispatch { it.calls += "x" })
        assertEquals(listOf("x"), new.calls.toList())
        assertEquals(listOf("start", "end"), old.calls.toList())
    }

    @Test
    fun `并发替换 较早的 attach 不能覆盖较新的监听`() {
        val gate = InterfaceListenerGate<Listener>()
        val old = Listener("old")
        val b = Listener("b")
        val c = Listener("c")
        gate.attach(old)

        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val inFlight = pool.submit {
            gate.dispatch { _ ->
                entered.countDown()
                release.await(30, TimeUnit.SECONDS)
            }
        }
        assertTrue(entered.await(30, TimeUnit.SECONDS))

        val gen0 = gate.generation()
        val resultB = pool.submit<InterfaceListenerGate.AttachResult> { gate.attach(b) }
        spinUntil("B to start waiting") { gate.generation() != gen0 }
        val genB = gate.generation()
        val resultC = pool.submit<InterfaceListenerGate.AttachResult> { gate.attach(c) }
        spinUntil("C to supersede B") { gate.generation() != genB }

        // B 被取代：不等旧回调就返回，且不发布 b。
        assertEquals(InterfaceListenerGate.AttachResult.Superseded, resultB.get(30, TimeUnit.SECONDS))
        assertFalse(resultC.isDone) // C 仍在等旧回调排空
        release.countDown()
        inFlight.get(30, TimeUnit.SECONDS)
        assertEquals(InterfaceListenerGate.AttachResult.Installed, resultC.get(30, TimeUnit.SECONDS))

        assertTrue(gate.dispatch { it.calls += "x" })
        assertEquals(listOf("x"), c.calls.toList())
        assertTrue(b.calls.isEmpty() && old.calls.isEmpty())
    }

    @Test
    fun `排空超时 明确失败 不安装新监听 且之后还能恢复`() {
        val gate = InterfaceListenerGate<Listener>(drainTimeoutMillis = 100)
        val old = Listener("old")
        val new = Listener("new")
        gate.attach(old)

        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val inFlight = pool.submit {
            gate.dispatch { _ ->
                entered.countDown()
                release.await(30, TimeUnit.SECONDS)
            }
        }
        assertTrue(entered.await(30, TimeUnit.SECONDS))

        assertEquals(InterfaceListenerGate.AttachResult.DrainTimeout, gate.attach(new))
        assertFalse("超时不能把新监听装上去", gate.hasListener())
        assertFalse(gate.dispatch { it.calls += "x" })
        assertTrue(new.calls.isEmpty())

        release.countDown()
        inFlight.get(30, TimeUnit.SECONDS)
        // 旧回调终于返回之后，重新 attach 正常生效。
        assertEquals(InterfaceListenerGate.AttachResult.Installed, gate.attach(new))
        assertTrue(gate.dispatch { it.calls += "y" })
        assertEquals(listOf("y"), new.calls.toList())
    }

    @Test
    fun `过期代次的派发被丢弃`() {
        val gate = InterfaceListenerGate<Listener>()
        val a = Listener("a")
        val b = Listener("b")
        gate.attach(a)
        val gen = gate.generation()
        gate.attach(b)
        assertFalse(gate.dispatch(gen) { it.calls += "stale" })
        assertTrue(a.calls.isEmpty() && b.calls.isEmpty())
        assertTrue(gate.dispatch(gate.generation()) { it.calls += "fresh" })
        assertEquals(listOf("fresh"), b.calls.toList())
    }

    @Test
    fun `回调里请求撤下监听不会等自己`() {
        val gate = InterfaceListenerGate<Listener>(drainTimeoutMillis = 30_000)
        val l = Listener("l")
        gate.attach(l)
        val done = pool.submit {
            gate.dispatch { gate.attach(null) } // 内核在回调里请求停止监听
        }
        done.get(30, TimeUnit.SECONDS)
        assertFalse(gate.hasListener())
    }

    @Test
    fun `没有监听时派发什么都不做`() {
        val gate = InterfaceListenerGate<Listener>()
        assertFalse(gate.dispatch { throw AssertionError("不该被调用") })
        gate.attach(null)
        assertFalse(gate.hasListener())
    }
}
