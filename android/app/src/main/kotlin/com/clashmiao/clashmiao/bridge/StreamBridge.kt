package com.clashmiao.clashmiao.bridge

import android.util.Log
import androidx.lifecycle.Observer
import com.clashmiao.clashmiao.MainActivity
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.engine.LibboxCommandStream
import com.clashmiao.clashmiao.engine.OutboundSnapshot
import com.google.gson.Gson
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
 * 5 条 EventChannel 在这一个类里注册，按驱动源分两组：
 *
 *   - **LiveData driven**（[CHANNEL_STATUS] / [CHANNEL_ALERTS]）：
 *     MainActivity 持有的 LiveData，sink 通过 `observeForever` 订阅。
 *   - **LibboxCommandStream driven**（[CHANNEL_STATS] / [CHANNEL_GROUPS] /
 *     [CHANNEL_GROUPS_LITE]）：listen 时连一条对应 StreamKind 的 sing-box
 *     command client，cancel 时断开。
 *   - LogBuffer 直接订阅：[CHANNEL_LOGS] 走 [MainActivity.logBuffer.subscriber]。
 *
 * 每个流的注册都走同一个 [SinkBinding] 抽象，[onAttachedToEngine] 一次性
 * 把它们都拉起来。
 */
class StreamBridge : FlutterPlugin {

    companion object {
        private const val TAG = "A/StreamBridge"
        private const val CHANNEL_STATUS = "com.clashmiao.app/service.status"
        private const val CHANNEL_ALERTS = "com.clashmiao.app/service.alerts"
        private const val CHANNEL_STATS = "com.clashmiao.app/stats"
        private const val CHANNEL_GROUPS = "com.clashmiao.app/groups"
        private const val CHANNEL_GROUPS_LITE = "com.clashmiao.app/active-groups"
        private const val CHANNEL_LOGS = "com.clashmiao.app/service.logs"
        private val gson = Gson()
    }

    /** 默认 scope；可被 [installScope] 替换为带 lifecycle 的 scope。 */
    private var scope: CoroutineScope? = null
    private val bindings = mutableListOf<SinkBinding>()

    /** MainActivity 在 configureFlutterEngine 里调一次，把 lifecycle scope 注入。 */
    fun installScope(scope: CoroutineScope) {
        this.scope = scope
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val msg = binding.binaryMessenger
        // 1. LiveData 驱动：status + alerts
        bindings += jsonStream(msg, CHANNEL_STATUS, StatusSource(TAG))
        bindings += jsonStream(msg, CHANNEL_ALERTS, AlertsSource(TAG))
        // 2. LibboxCommandStream 驱动：stats（JSON 编码）+ groups + groups-lite
        bindings += jsonStream(msg, CHANNEL_STATS, StatsSource())
        bindings += standardStream(msg, CHANNEL_GROUPS, GroupsSource(LibboxCommandStream.StreamKind.FULL_GROUPS))
        bindings += standardStream(msg, CHANNEL_GROUPS_LITE, GroupsSource(LibboxCommandStream.StreamKind.GROUP_INFO_ONLY))
        // 3. logs：直接吃 LogBuffer.subscriber，不走 libbox command client。
        bindings += standardStream(msg, CHANNEL_LOGS, LogsSource())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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
//  LiveData 驱动的两个流
// ===================================================================

private class StatusSource(private val tag: String) : StreamSource {
    private var observer: Observer<KernelStatus>? = null
    override fun start(sink: EventChannel.EventSink) {
        val obs = Observer<KernelStatus> { status ->
            Log.d(tag, "status → $status")
            // 单字段 map，Dart 端按 'status' key 取值。
            sink.success(mapOf("status" to status.name))
        }
        observer = obs
        MainActivity.instance.serviceStatus.observeForever(obs)
    }

    override fun stop() {
        observer?.let { MainActivity.instance.serviceStatus.removeObserver(it) }
        observer = null
    }
}

private class AlertsSource(private val tag: String) : StreamSource {
    private var observer: Observer<ServiceEvent?>? = null
    override fun start(sink: EventChannel.EventSink) {
        val obs = Observer<ServiceEvent?> { event ->
            if (event == null) return@Observer
            Log.d(tag, "alert → $event")
            // 只把非 null 字段编进 map（Dart 端 None 用字段缺失表示）。
            val payload = HashMap<String, String>(3).apply {
                put("status", event.status.name)
                event.alert?.let { put("alert", it.name) }
                event.message?.let { put("message", it) }
            }
            sink.success(payload)
        }
        observer = obs
        MainActivity.instance.serviceAlerts.observeForever(obs)
    }

    override fun stop() {
        observer?.let { MainActivity.instance.serviceAlerts.removeObserver(it) }
        observer = null
    }
}

// ===================================================================
//  LibboxCommandStream subscriber 实现
// ===================================================================

private class StatsSubscriber(private val sink: EventChannel.EventSink) :
    LibboxCommandStream.Subscriber {

    override fun onStats(message: StatusMessage) {
        MainActivity.instance.runOnUiThread {
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

    private val gson = Gson()

    override fun onGroups(groups: List<OutboundGroup>) {
        MainActivity.instance.runOnUiThread {
            val payload = groups.map { OutboundSnapshot.from(it) }
            sink.success(gson.toJson(payload))
        }
    }
}

private class LogsSource : StreamSource {
    private var attachedSink: EventChannel.EventSink? = null
    override fun start(sink: EventChannel.EventSink) {
        attachedSink = sink
        val buffer = MainActivity.instance.logBuffer
        // 首次订阅先把缓冲快照推给 Dart。
        sink.success(buffer.snapshot())
        buffer.subscriber = {
            attachedSink?.success(buffer.snapshot())
        }
    }

    override fun stop() {
        MainActivity.instance.logBuffer.subscriber = null
        attachedSink = null
    }
}
