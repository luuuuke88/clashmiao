package com.clashmiao.clashmiao.engine

import android.util.Log
import com.clashmiao.libcore.core.Engine
import com.clashmiao.libcore.core.GroupsHandler
import com.clashmiao.libcore.core.StatsHandler
import com.clashmiao.libcore.core.Subscription
import go.Seq
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 单条内核流（统计 / 分组）的订阅管理 —— 内核的 Stats / Groups 推送通过这个对象订阅一次。
 *
 * 使用形态：
 *   - `CoreStream(scope, StreamKind.STATS, mySubscriber).connect()`
 *   - 想停的时候 `.disconnect()`
 *
 * 设计要点：
 *   - 内核实例（[EngineRegistry.current]）在服务初始化前订阅会失败（没有 Engine / 命令服务器没就绪）。
 *     这里走最多 10 次的间隔重试（每次 100ms + i*50ms），第一次成功就退出。
 *   - 重试期间如果调用 [disconnect]（或又 connect 了一次）、或父 coroutine 被取消，
 *     这次尝试按代际作废：候选连接自己丢弃，不会留 ghost 订阅。
 *   - 载荷是 Go 产出的 JSON 字符串，这里**不解析**：分组原样透传，统计在 [StreamBridge] 里转成数字 Map（线格式契约）。
 *   - [Subscriber] 只暴露我们 app 真正用到的两条事件（stats / groups）。
 *   - 订阅断线（内核停止）只记日志：重连由 [InstanceFollower] 跟随内核实例驱动，不在这里自己重连。
 */
class CoreStream internal constructor(
    private val scope: CoroutineScope,
    private val newClient: () -> Client,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val backoff: suspend (attempt: Int) -> Unit = { delay(BASE_BACKOFF_MS + it * BACKOFF_STEP_MS) },
) {

    constructor(scope: CoroutineScope, kind: StreamKind, subscriber: Subscriber) :
        this(scope, { EngineClient(kind, subscriber) { EngineRegistry.current } })

    /** 哪种流。 */
    enum class StreamKind { STATS, GROUPS }

    /** 订阅者只需要管自己关心的事件；载荷是 Go 产出的 JSON 文本。 */
    interface Subscriber {
        fun onStats(json: String) = Unit
        fun onGroups(json: String) = Unit
    }

    /** 一条订阅客户端（生产实现包 Engine 的订阅；测试用假实现）。 */
    internal interface Client {
        /** 阻塞连接；内核未就绪时抛异常。 */
        fun connect()

        /** 放弃从未被采用的候选连接。 */
        fun abandon()

        /** 关闭已采用的连接并释放 jni ref。 */
        fun close()
    }

    // 代际：每次 connect / disconnect 都开新的一代；后台连接尝试只有仍是当前代才会被采用，
    // 否则（期间被 disconnect 或又 connect 了一次）自己丢弃候选，不留 ghost client。
    private val lock = Any()
    private var generation = 0L
    private var live: Client? = null
    private var pending: Job? = null

    /** 当前是否持有一条已采用的连接（测试用）。 */
    internal val isConnected: Boolean get() = synchronized(lock) { live != null }

    /**
     * 启动连接。多次调用 [connect] 时，老连接会先被 disconnect。
     * 真正的连接尝试在后台异步跑，最多 10 次。
     */
    fun connect() {
        synchronized(lock) {
            closeLocked()
            val gen = generation
            pending = scope.launch(dispatcher) {
                val candidate = synchronized(lock) {
                    if (gen != generation) return@launch
                    newClient()
                }
                var adopted = false
                try {
                    val ok = attemptWithBackoff(candidate)
                    synchronized(lock) {
                        if (ok && isActive && gen == generation) {
                            live = candidate
                            pending = null
                            adopted = true
                        }
                    }
                    if (!ok) Log.w(TAG, "stream client gave up after $MAX_ATTEMPTS attempts")
                } finally {
                    if (!adopted) runCatching { candidate.abandon() }
                }
            }
        }
    }

    /**
     * 至多 [MAX_ATTEMPTS] 次循环尝试 connect()，每次 backoff 时长按 attempt index 线性递增。
     * 任意一次成功就返回 true；中途 cancel 也算 false。
     */
    private suspend fun attemptWithBackoff(candidate: Client): Boolean {
        for (attempt in 1..MAX_ATTEMPTS) {
            backoff(attempt)
            try {
                candidate.connect()
                return true
            } catch (_: Exception) {
                // sing-box 还没起来，下一轮再试
                continue
            }
        }
        return false
    }

    /** 断开当前连接、作废在途的连接尝试。空闲调用安全。 */
    fun disconnect() {
        synchronized(lock) { closeLocked() }
    }

    private fun closeLocked() {
        generation++
        pending?.cancel()
        pending = null
        val current = live ?: return
        live = null
        runCatching { current.close() }
    }

    // === 内核订阅客户端 ======================================================

    private class EngineClient(
        private val kind: StreamKind,
        private val subscriber: Subscriber,
        private val engine: () -> Engine?,
    ) : Client {
        @Volatile private var sub: Subscription? = null

        override fun connect() {
            val e = engine() ?: throw IllegalStateException("kernel engine is not ready")
            sub = when (kind) {
                StreamKind.GROUPS -> e.subscribeGroups(GroupsBridge(subscriber))
                StreamKind.STATS -> e.subscribeStats(StatsBridge(subscriber), STATS_INTERVAL_MILLIS)
            }
        }

        override fun abandon() {
            release(destroyRef = false)
        }

        override fun close() {
            release(destroyRef = true)
        }

        private fun release(destroyRef: Boolean) {
            val s = sub ?: return
            sub = null
            runCatching { s.close() }
            if (destroyRef) runCatching { Seq.destroyRef(s.refnum) }
        }
    }

    // === 内核 → Kotlin 回调桥 ==============================================

    private class GroupsBridge(private val subscriber: Subscriber) : GroupsHandler {
        override fun onGroups(json: String) = subscriber.onGroups(json)
        override fun onDisconnected(message: String?) {
            Log.i(TAG, "groups stream disconnected: $message")
        }
    }

    private class StatsBridge(private val subscriber: Subscriber) : StatsHandler {
        override fun onStats(json: String) = subscriber.onStats(json)
        override fun onDisconnected(message: String?) {
            Log.i(TAG, "stats stream disconnected: $message")
        }
    }

    private companion object {
        private const val TAG = "engine/CoreStream"
        // 统计推送间隔：2 秒。
        private const val STATS_INTERVAL_MILLIS: Long = 2_000
        private const val MAX_ATTEMPTS = 10
        private const val BASE_BACKOFF_MS = 100L
        private const val BACKOFF_STEP_MS = 50L
    }
}
