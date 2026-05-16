package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.drain
import go.Seq
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 单条 libbox 流命令的连接管理 —— sing-box 的 Status / Groups / Log / Clash 等推送
 * 通过这个对象订阅一次性的 streaming command。
 *
 * 使用形态：
 *   - `LibboxCommandStream(scope, StreamKind.STATS, mySubscriber).connect()`
 *   - 想停的时候 `.disconnect()`
 *
 * 设计要点：
 *   - libbox 自己的 `CommandClient`（go-jni 那一边的）在 service 初始化前调 `connect()`
 *     会 throw。这里走最多 10 次的间隔重试（每次 100ms + i*50ms），第一次成功就退出。
 *   - 重试期间如果调用 [disconnect] 或父 coroutine 被取消，就直接释放后退出，
 *     不会留 ghost client。
 *   - [Subscriber] 接口只暴露我们 app 真正用到的两条事件（status / groups）。
 *     libbox 还有 clearLog / writeLog / clashMode 那些 callback 我们不订阅，
 *     所以这层都不暴露，少一个 API surface 就少一份维护成本。
 */
class LibboxCommandStream(
    private val scope: CoroutineScope,
    private val kind: StreamKind,
    private val subscriber: Subscriber,
) {

    /** 哪种流。libbox 用 int command code 区分，这里映射到一个 enum 用着舒服点。 */
    enum class StreamKind(val command: Int) {
        STATS(Libbox.CommandStatus),
        FULL_GROUPS(Libbox.CommandGroup),
        GROUP_INFO_ONLY(Libbox.CommandGroupInfoOnly),
    }

    /** 订阅者只需要管自己关心的事件。 */
    interface Subscriber {
        fun onStats(message: StatusMessage) = Unit
        fun onGroups(groups: List<OutboundGroup>) = Unit
    }

    @Volatile
    private var live: CommandClient? = null

    private val callbackBridge = SubscriberBridge()

    /**
     * 启动连接。多次调用 [connect] 时，老连接会先被 disconnect。
     * 真正的连接尝试在 IO scope 内异步跑，最多 10 次。
     */
    @OptIn(DelicateCoroutinesApi::class)
    fun connect() {
        disconnect()
        val options = CommandClientOptions().also {
            it.command = kind.command
            it.statusInterval = STATS_INTERVAL_NANOS
        }
        val candidate = CommandClient(callbackBridge, options)
        scope.launch(Dispatchers.IO) {
            val ok = attemptWithBackoff(candidate)
            if (!ok || !isActive) {
                runCatching { candidate.disconnect() }
                return@launch
            }
            live = candidate
        }
    }

    /**
     * 至多 [MAX_ATTEMPTS] 次循环尝试 connect()，每次 backoff 时长按 attempt index 线性递增。
     * 任意一次成功就返回 true；中途 cancel 也算 false。
     */
    private suspend fun attemptWithBackoff(candidate: CommandClient): Boolean {
        for (attempt in 1..MAX_ATTEMPTS) {
            delay(BASE_BACKOFF_MS + attempt * BACKOFF_STEP_MS)
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

    /** 把当前活动的 libbox client 断开 + 释放 jni ref。空闲调用安全。 */
    fun disconnect() {
        val current = live ?: return
        runCatching { current.disconnect() }
        Seq.destroyRef(current.refnum)
        live = null
    }

    // === libbox → Kotlin 回调桥 ===========================================

    private inner class SubscriberBridge : CommandClientHandler {
        override fun connected() = Unit
        override fun disconnected(message: String?) = Unit
        override fun clearLog() = Unit
        override fun writeLog(message: String?) = Unit
        override fun initializeClashMode(modeList: StringIterator, currentMode: String) {
            // app 没用 clash-mode UI，只 drain 一下 iterator 避免 jni 端泄漏
            modeList.drain()
        }

        override fun updateClashMode(newMode: String) = Unit

        override fun writeStatus(message: StatusMessage?) {
            val msg = message ?: return
            subscriber.onStats(msg)
        }

        override fun writeGroups(message: OutboundGroupIterator?) {
            val iter = message ?: return
            val out = ArrayList<OutboundGroup>()
            while (iter.hasNext()) out.add(iter.next())
            subscriber.onGroups(out)
        }
    }

    private companion object {
        // libbox status 推送间隔：2 秒（纳秒制）。
        private const val STATS_INTERVAL_NANOS: Long = 2L * 1000 * 1000 * 1000
        private const val MAX_ATTEMPTS = 10
        private const val BASE_BACKOFF_MS = 100L
        private const val BACKOFF_STEP_MS = 50L
    }
}
