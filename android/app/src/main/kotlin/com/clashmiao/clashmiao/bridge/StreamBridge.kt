package com.clashmiao.clashmiao.bridge

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.Observer
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.engine.KernelCoordinator
import com.clashmiao.clashmiao.engine.InstanceFollower
import com.clashmiao.clashmiao.engine.KernelSnapshot
import com.clashmiao.clashmiao.engine.CoreStream
import com.clashmiao.clashmiao.engine.LogBuffer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.JSONMethodCodec
import org.json.JSONObject
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
 *   - **CoreStream driven**（[CHANNEL_STATS] / [CHANNEL_GROUPS]）：listen 时订阅内核对应的流，
 *     cancel 时断开；监听期间每个新启动的内核实例都重连一次。
 *     载荷是内核（Go）产出的 JSON：**分组原样透传 `String`**，**统计解析成数字 `Map<String, Long>`** 再发——
 *     Dart 只认 Map，把统计当字符串发过去会被静默当成全零（[StreamWire]）。
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
        private const val CHANNEL_LOGS = "com.clashmiao.app/service.logs"
        private const val CHANNEL_NETWORK = "com.clashmiao.app/network"

        /** 统计流的 EventChannel：JSON codec（信封是 JSON 文本，Dart 端 `JSONMethodCodec`）。 */
        internal fun statsChannel(msg: BinaryMessenger) = EventChannel(msg, CHANNEL_STATS, JSONMethodCodec.INSTANCE)

        /** 分组流的 EventChannel：默认 Standard codec（载荷是 String）。 */
        internal fun groupsChannel(msg: BinaryMessenger) = EventChannel(msg, CHANNEL_GROUPS)

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
        // 2. CoreStream 驱动：stats（JSON 信封）+ groups（Standard 信封）。
        //    旧的「仅活动分组」流（active-groups）没有任何 Dart 订阅者（取证：lib/ 与 pigeons/ 里没有该通道名），已删除。
        bindings += SinkBinding(statsChannel(msg), StatsSource())
        bindings += SinkBinding(groupsChannel(msg), GroupsSource())
        // 3. logs：直接吃 LogBuffer.subscriber（内核日志经 Platform.writeLog 进缓冲）。
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

    private inner class StatsSource : FollowingCommandSource("stats") {
        override fun open(scope: CoroutineScope, sink: EventChannel.EventSink) =
            CoreStream(scope, CoreStream.StreamKind.STATS, StatsSubscriber(sink))
    }

    private inner class GroupsSource : FollowingCommandSource("groups") {
        override fun open(scope: CoroutineScope, sink: EventChannel.EventSink) =
            CoreStream(scope, CoreStream.StreamKind.GROUPS, GroupsSubscriber(sink))
    }

    /**
     * 由内核订阅驱动的流：Dart 监听期间，跟随当前内核实例——每出现一个新的已
     * 启动实例（epoch / attempt 变化）就重连一次，不依赖 Dart 侧何时取消、
     * 重新监听（见 [InstanceFollower]）。连上新实例后内核会先推一次当前值（分组 / 统计）。
     */
    private abstract inner class FollowingCommandSource(private val name: String) : StreamSource {
        private var stream: CoreStream? = null
        private var observer: Observer<KernelSnapshot>? = null
        private val follower = InstanceFollower()

        abstract fun open(scope: CoroutineScope, sink: EventChannel.EventSink): CoreStream

        override fun start(sink: EventChannel.EventSink) {
            stop()
            val coroutineScope = scope ?: return
            val live = KernelCoordinator.snapshotLive
            follower.attach(live.value)
            val opened = open(coroutineScope, sink).also { it.connect() }
            stream = opened
            val obs = Observer<KernelSnapshot> { snapshot ->
                if (follower.onSnapshot(snapshot)) {
                    Log.i(TAG, "$name: 内核实例 ${snapshot.epoch}/${snapshot.attempt} 已启动，重连内核流")
                    opened.connect()
                }
            }
            observer = obs
            live.observeForever(obs)
        }

        override fun stop() {
            observer?.let { KernelCoordinator.snapshotLive.removeObserver(it) }
            observer = null
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
//  CoreStream subscriber 实现
// ===================================================================

/**
 * 内核推给 Dart 的两类载荷的线格式（契约由 Go 侧产出并用黄金文件锁定，见 kernel/testdata/wire）：
 *   - 分组：JSON 文本（`[{tag,type,selected,items:[{tag,type,url-test-delay}]}]`），**原样透传 String**；
 *   - 统计：Go 给的 JSON 对象解析成 6 个键的 `Map<String, Long>`，Dart 只认 Map。
 */
internal object StreamWire {
    /** 统计载荷的键，顺序固定（线格式契约）。 */
    val STATS_KEYS = listOf(
        "connections-in", "connections-out", "uplink", "downlink", "uplink-total", "downlink-total",
    )

    /** 统计 JSON → 6 个键的数字 Map；缺键或不是整数都视为协议违规（抛异常，由调用方丢弃这一帧并记日志）。 */
    fun statsMap(json: String): Map<String, Long> {
        val o = JSONObject(json)
        val out = LinkedHashMap<String, Long>(STATS_KEYS.size)
        for (k in STATS_KEYS) {
            require(o.has(k)) { "stats frame lacks key $k" }
            out[k] = o.getLong(k)
        }
        return out
    }
}

internal class StatsSubscriber(private val sink: EventChannel.EventSink) : CoreStream.Subscriber {
    override fun onStats(json: String) {
        val payload = try {
            StreamWire.statsMap(json)
        } catch (e: Exception) {
            Log.w("A/StreamBridge", "drop malformed stats frame: ${e.message}")
            return
        }
        StreamBridge.postMain { sink.success(payload) }
    }
}

internal class GroupsSubscriber(private val sink: EventChannel.EventSink) : CoreStream.Subscriber {
    override fun onGroups(json: String) {
        StreamBridge.postMain { sink.success(json) }
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
        // 日志可能来自任意线程（内核回调）：合并成一次主线程投递，每次推完整快照。
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
