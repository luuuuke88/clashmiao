package com.clashmiao.clashmiao.engine

/**
 * 动态通知更新（统计流 + 屏幕开关广播）的代际归属。纯 Kotlin，JVM 可测。
 *
 * 每次内核就绪 [begin] 开一代，[stop]（回收 / 退休 / onDestroy）结束当前代。后台的启动任务
 * [runStart] 只在自己仍是当前代时才连接统计流、注册广播；复查代际与连接、注册在同一个锁内，
 * 与 [stop] 互斥——所以不存在「复查通过之后才被停止」的窗口，迟到的任务什么也不会留下。
 */
class NoticeUpdates(private val ops: Ops) {

    interface Ops {
        /** 用户是否开了动态通知（读设置，可能慢）。 */
        fun dynamicEnabled(): Boolean
        fun connectStats()
        fun disconnectStats()
        fun registerScreen()
        fun unregisterScreen()
    }

    private val lock = Any()
    private var generation = 0L
    private var statsWanted = false
    private var screenArmed = false

    /** 开新的一代（主线程）；返回值交给后台的 [runStart]。 */
    fun begin(): Long = synchronized(lock) { ++generation }

    /** 后台执行：本代仍有效时才连接统计流并注册屏幕广播。 */
    fun runStart(gen: Long) {
        if (!isCurrent(gen)) return
        if (!ops.dynamicEnabled()) return
        // 复查与连接 / 注册在同一个临界区里：[stop] 要么在它之前（这里什么也不做），
        // 要么在它之后（把这里建立的一切撤掉），不存在中间态。
        synchronized(lock) {
            if (gen != generation) return
            if (!statsWanted) {
                ops.connectStats()
                statsWanted = true
            }
            if (!screenArmed) {
                ops.registerScreen()
                screenArmed = true
            }
        }
    }

    /** 结束当前代：断开统计流、注销屏幕广播；之后到达的旧任务一律作废。 */
    fun stop() {
        synchronized(lock) { stopLocked() }
    }

    private fun stopLocked() {
        generation++
        if (statsWanted) {
            statsWanted = false
            runCatching { ops.disconnectStats() }
        }
        if (screenArmed) {
            screenArmed = false
            runCatching { ops.unregisterScreen() }
        }
    }

    /** 屏幕亮 / 灭：只在本代仍要统计流时才改连接。 */
    fun onScreen(on: Boolean) {
        synchronized(lock) {
            if (!statsWanted) return
            if (on) ops.connectStats() else ops.disconnectStats()
        }
    }

    fun isCurrent(gen: Long): Boolean = synchronized(lock) { gen == generation }
}
