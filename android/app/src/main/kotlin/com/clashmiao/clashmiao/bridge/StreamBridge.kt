package com.clashmiao.clashmiao.bridge

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.Observer
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.engine.KernelCoordinator
import com.clashmiao.clashmiao.engine.KernelSnapshot
import com.clashmiao.clashmiao.engine.LibboxCommandStream
import com.clashmiao.clashmiao.engine.LogBuffer
import com.clashmiao.clashmiao.engine.OutboundSnapshot
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.JSONMethodCodec
import io.nekohasekai.libbox.OutboundGroup
import io.nekohasekai.libbox.StatusMessage
import kotlinx.coroutines.CoroutineScope

/**
 * 内核 → Dart 单向推送流的总入口。
 *
 * EventChannel 在这一个类里注册，按驱动源分三组：
 *
 *   - **进程级协调器驱动**：[CHANNEL_KERNEL_SNAPSHOT] 是权威快照（JSON map，订阅时先推当前值）；
 *     旧的 [CHANNEL_STATUS] 只是从同一份快照派生的兼容流（仅在 status 变化时推）；
 *     [CHANNEL_ALERTS] 只保留**非生命周期**提示（如通知权限被拒）——启动失败等
 *     生命周期事实一律在快照的 lastFailure 里，不再另发 alert。
 *   - **LibboxCommandStream driven**（[CHANNEL_STATS] / [CHANNEL_GROUPS] /
 *     [CHANNEL_GROUPS_LITE]）：listen 时连一条对应 StreamKind 的 sing-box
 *     command client，cancel 时断开。
 *   - LogBuffer 直接订阅：[CHANNEL_LOGS] 观察协调器持有的进程级日志缓冲，主线程投递。
 *
 * 每个流的注册都走同一个 [SinkBinding] 抽象，[onAttachedToEngine] 一次性
 * 把它们都拉起来。
 */
class StreamBridge : FlutterPlugin {

    companion object {
        private const val TAG = "A/StreamBridge"
        private const val CHANNEL_KERNEL_SNAPSHOT = "com.clashmiao.app/kernel.snapshot"
        private const val CHANNEL_STATUS = "com.clashmiao.app/service.status"
        private const val CHANNEL_ALERTS = "com.clashmiao.app/service.alerts"
        private const val CHANNEL_STATS = "com.clashmiao.app/stats"
        private const val CHANNEL_GROUPS = "com.clashmiao.app/groups"
        private const val CHANNEL_GROUPS_LITE = "com.clashmiao.app/active-groups"
        private const val CHANNEL_LOGS = "com.clashmiao.app/service.logs"
        private const val CHANNEL_NETWORK = "com.clashmiao.app/network"
        /** 唯一实例引用，供 NetworkWatcher 等原生组件推送事件。 */
        @Volatile var instance: StreamBridge? = null
            private set

        private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

        /** 把工作交到主线程（EventSink 只能在主线程使用）。 */
        internal fun postMain(block: () -> Unit) {
            if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
        }
    }

    /** 默认 scope；可被 [installScope] 替换为带 lifecycle 的 scope。 */
    private var scope: CoroutineScope? = null
    private val bindings = mutableListOf<SinkBinding>()

    /** network EventChannel 的当前 sink（主线程写，主线程读）。 */
    @Volatile private var networkSink: EventChannel.EventSink? = null

    /** MainActivity 在 configureFlutterEngine 里调一次，把 lifecycle scope 注入。 */
    fun installScope(scope: CoroutineScope) {
        this.scope = scope
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = this
        val msg = binding.binaryMessenger
        // 1. 协调器驱动：权威快照 + 兼容的 status / 非生命周期 alerts
        bindings += jsonStream(msg, CHANNEL_KERNEL_SNAPSHOT, SnapshotSource())
        bindings += jsonStream(msg, CHANNEL_STATUS, StatusSource(TAG))
        bindings += jsonStream(msg, CHANNEL_ALERTS, AlertsSource(TAG))
        // 2. LibboxCommandStream 驱动：stats（JSON 编码）+ groups + groups-lite
        bindings += jsonStream(msg, CHANNEL_STATS, StatsSource())
        bindings += standardStream(msg, CHANNEL_GROUPS, GroupsSource(LibboxCommandStream.StreamKind.FULL_GROUPS))
        bindings += standardStream(msg, CHANNEL_GROUPS_LITE, GroupsSource(LibboxCommandStream.StreamKind.GROUP_INFO_ONLY))
        // 3. logs：直接吃 LogBuffer.subscriber，不走 libbox command client。
        bindings += standardStream(msg, CHANNEL_LOGS, LogsSource())
        // 4. network：保留通道兼容旧订阅者；网络切换后的重载由原生协调器自己决定，不再通知 Dart。
        EventChannel(msg, CHANNEL_NETWORK).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                networkSink = events
            }
            override fun onCancel(arguments: Any?) {
                networkSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        instance = null
        networkSink = null
        bindings.forEach { it.detach() }
        bindings.clear()
    }

    // === 通用 sink binding helper ==========================================

    private fun jsonStream(msg: BinaryMessenger, name: String, source: StreamSource) =
        SinkBinding(EventChannel(msg, name, JSONMethodCodec.INSTANCE), source)

    private fun standardStream(msg: BinaryMessenger, name: String, source: StreamSource) =
        SinkBinding(EventChannel(msg, name), source)

    private inner class StatsSource : StreamSource {
        private var stream: LibboxCommandStream? = null
        override fun start(sink: EventChannel.EventSink) {
            val coroutineScope = scope ?: return
            stream = LibboxCommandStream(
                coroutineScope,
                LibboxCommandStream.StreamKind.STATS,
                StatsSubscriber(sink),
            ).also { it.connect() }
        }

        override fun stop() {
            stream?.disconnect()
            stream = null
        }
    }

    private inner class GroupsSource(private val kind: LibboxCommandStream.StreamKind) : StreamSource {
        private var stream: LibboxCommandStream? = null
        override fun start(sink: EventChannel.EventSink) {
            val coroutineScope = scope ?: return
            stream = LibboxCommandStream(coroutineScope, kind, GroupsSubscriber(sink))
                .also { it.connect() }
        }

        override fun stop() {
            stream?.disconnect()
            stream = null
        }
    }
}

// ===================================================================
//  ServiceEvent
// ===================================================================

/** Alerts channel 的载荷：内核 / VPN 层非致命错误。注意字段名直接被 .name 序列化。 */
data class ServiceEvent(
    val status: KernelStatus,
    val alert: AlertCode? = null,
    val message: String? = null,
)

// ===================================================================
//  SinkBinding / StreamSource —— 把 EventChannel.StreamHandler 那一坨
//  样板代码（onListen / onCancel + null sink 保护）抽出来。
// ===================================================================

private interface StreamSource {
    fun start(sink: EventChannel.EventSink)
    fun stop()
}

private class SinkBinding(
    private val channel: EventChannel,
    private val source: StreamSource,
) : EventChannel.StreamHandler {

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        source.start(events)
    }

    override fun onCancel(arguments: Any?) {
        source.stop()
    }

    fun detach() {
        source.stop()
        channel.setStreamHandler(null)
    }
}

// ===================================================================
//  协调器驱动的三个流
// ===================================================================

/** 观察进程级快照 LiveData（只在主线程 setValue；observeForever 订阅即回放当前值）。 */
private abstract class SnapshotObserverSource : StreamSource {
    private var observer: Observer<KernelSnapshot>? = null

    protected abstract fun onSnapshot(sink: EventChannel.EventSink, snapshot: KernelSnapshot)
    protected open fun onStart() = Unit

    override fun start(sink: EventChannel.EventSink) {
        stop()
        onStart()
        val obs = Observer<KernelSnapshot> { onSnapshot(sink, it) }
        observer = obs
        KernelCoordinator.snapshotLive.observeForever(obs)
    }

    override fun stop() {
        observer?.let { KernelCoordinator.snapshotLive.removeObserver(it) }
        observer = null
    }
}

/** 权威快照：订阅时先推当前值，之后每次变化推一次。 */
private class SnapshotSource : SnapshotObserverSource() {
    override fun onSnapshot(sink: EventChannel.EventSink, snapshot: KernelSnapshot) {
        sink.success(snapshot.toWireMap())
    }
}

/** 旧 status 流：从快照派生，仅在 status 变化时推（与旧 LiveData 的「每次 set 都推」相比不再重复）。 */
private class StatusSource(private val tag: String) : SnapshotObserverSource() {
    private var last: KernelStatus? = null

    override fun onStart() {
        last = null
    }

    override fun onSnapshot(sink: EventChannel.EventSink, snapshot: KernelSnapshot) {
        if (snapshot.status == last) return
        last = snapshot.status
        Log.d(tag, "status → ${snapshot.status}")
        // 单字段 map，Dart 端按 'status' key 取值。
        sink.success(mapOf("status" to snapshot.status.name))
    }
}

/** 非生命周期提示（不粘性：订阅者不会收到订阅之前的旧 alert）。 */
private class AlertsSource(private val tag: String) : StreamSource {
    private var dispose: (() -> Unit)? = null
    override fun start(sink: EventChannel.EventSink) {
        dispose?.invoke()
        dispose = KernelCoordinator.instance.observeAlerts { code, message ->
            val event = ServiceEvent(KernelStatus.Stopped, code, message)
            Log.d(tag, "alert → $event")
            // 只把非 null 字段编进 map（Dart 端 None 用字段缺失表示）。
            val payload = HashMap<String, String>(3).apply {
                put("status", event.status.name)
                event.alert?.let { put("alert", it.name) }
                event.message?.let { put("message", it) }
            }
            sink.success(payload)
        }
    }

    override fun stop() {
        dispose?.invoke()
        dispose = null
    }
}

// ===================================================================
//  LibboxCommandStream subscriber 实现
// ===================================================================

private class StatsSubscriber(private val sink: EventChannel.EventSink) :
    LibboxCommandStream.Subscriber {

    override fun onStats(message: StatusMessage) {
        StreamBridge.postMain {
            sink.success(
                mapOf(
                    "connections-in" to message.connectionsIn,
                    "connections-out" to message.connectionsOut,
                    "uplink" to message.uplink,
                    "downlink" to message.downlink,
                    "uplink-total" to message.uplinkTotal,
                    "downlink-total" to message.downlinkTotal,
                ),
            )
        }
    }
}

private class GroupsSubscriber(private val sink: EventChannel.EventSink) :
    LibboxCommandStream.Subscriber {

    override fun onGroups(groups: List<OutboundGroup>) {
        // 在回调线程上拍平（go 迭代器不跨线程），编码见 [OutboundSnapshot.encode]。
        val payload = OutboundSnapshot.encode(groups.map { OutboundSnapshot.from(it) })
        StreamBridge.postMain { sink.success(payload) }
    }
}

private class LogsSource : StreamSource {
    private var attachedSink: EventChannel.EventSink? = null
    private var buffer: LogBuffer? = null

    @Volatile private var pending = false

    override fun start(sink: EventChannel.EventSink) {
        attachedSink = sink
        val logs = KernelCoordinator.instance.logs
        buffer = logs
        // 首次订阅先把缓冲快照推给 Dart。
        sink.success(logs.snapshot())
        // 日志可能来自任意线程（libbox 回调）：合并成一次主线程投递，每次推完整快照。
        logs.subscriber = {
            if (!pending) {
                pending = true
                StreamBridge.postMain {
                    pending = false
                    attachedSink?.success(logs.snapshot())
                }
            }
        }
    }

    override fun stop() {
        buffer?.subscriber = null
        buffer = null
        attachedSink = null
    }
}
