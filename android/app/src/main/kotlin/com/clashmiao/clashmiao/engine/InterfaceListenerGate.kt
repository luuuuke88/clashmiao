package com.clashmiao.clashmiao.engine

import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * 内核默认接口监听的「代次 + 排空屏障」。
 *
 * 内核的接口回调会访问下一轮启动初始化的共享状态，所以「撤下旧监听」不能只是把引用置空：
 * 线程可以先取到旧监听、另一个线程完成撤下、再去调旧监听（置空只影响之后的读取）；已经进入回调的线程也没人等。
 * 这里把取监听与「进入在途」放在同一个临界区里，撤下 / 换新监听时：
 *   1. 代次 +1，当前监听清空（之后任何 [dispatch] 都拿不到旧监听）；
 *   2. 等已经进入的旧回调全部返回（排空屏障），再返回给调用方——调用方据此保证新一轮启动不与旧回调交错。
 *
 * 回调本身**不持锁**（它会跨 JNI 进内核，内核在里面可能回头调平台接口，持锁会和内核的锁互相等死）；
 * 等待用条件变量，等待期间也不占锁。回调线程自己调 [attach]（内核在回调里请求停止监听）时不等自己。
 */
internal class InterfaceListenerGate<L : Any>(private val drainTimeoutMillis: Long = DEFAULT_DRAIN_TIMEOUT_MS) {

    private val lock = ReentrantLock()
    private val drained = lock.newCondition()
    private var current: L? = null
    private var generation = 0L
    private var inFlight = 0

    /** 本线程当前嵌套在几层 [dispatch] 回调里（等排空时要把自己算进去，否则回调里 attach 会等自己）。 */
    private val depth = ThreadLocal.withInitial { 0 }

    fun hasListener(): Boolean = lock.withLock { current != null }

    /** 当前代次；调用方在开始一轮耗时的准备工作前取一次，之后 [dispatch] 带上它，代次变了就丢弃。 */
    fun generation(): Long = lock.withLock { generation }

    /** 换上 [listener]（null = 撤下）。返回时，所有旧监听的在途回调都已结束（或超时，见 [drainTimeoutMillis]）。 */
    fun attach(listener: L?) {
        lock.withLock {
            generation++
            current = null
            val mine = depth.get()!!
            var nanos = TimeUnit.MILLISECONDS.toNanos(drainTimeoutMillis)
            while (inFlight > mine && nanos > 0) {
                nanos = drained.awaitNanos(nanos)
            }
            current = listener
        }
    }

    /**
     * 对当前监听调一次 [block]。没有监听、或 [expectedGeneration] 非空且已经不是当前代次，则什么都不做并返回 false。
     */
    fun dispatch(expectedGeneration: Long? = null, block: (L) -> Unit): Boolean {
        val listener = lock.withLock {
            val l = current
            if (l == null || (expectedGeneration != null && expectedGeneration != generation)) return false
            inFlight++
            l
        }
        depth.set(depth.get()!! + 1)
        try {
            block(listener)
        } finally {
            depth.set(depth.get()!! - 1)
            lock.withLock {
                inFlight--
                if (inFlight == 0) drained.signalAll()
            }
        }
        return true
    }

    companion object {
        /** 排空等待的兜底（失败才会用到，不是正常路径上的等待手段）。 */
        const val DEFAULT_DRAIN_TIMEOUT_MS = 30_000L
    }
}
