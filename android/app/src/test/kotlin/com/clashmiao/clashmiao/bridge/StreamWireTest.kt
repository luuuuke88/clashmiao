package com.clashmiao.clashmiao.bridge

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.JSONMethodCodec
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.util.Base64

/**
 * 内核 → Dart 两条流的线格式契约（spec §4.2）：Go 产出载荷，Kotlin 只透传（分组）或解析成数字 Map（统计），
 * 再经**真实的 EventChannel 与 codec** 编成信封，Dart 用同一份信封黄金文件解码。
 *
 * 载荷夹具 `groups-first.json` / `stats-frame.json` 由 Go 的测试产出并锁定；信封黄金文件
 * `stats-envelope.json` / `groups-envelope.b64` 由本测试经真实通道编码得到，`UPDATE_GOLDEN=1` 重写（diff 进评审）。
 * 不手工构造 Map 绕过 codec：测试驱动的是生产代码里的通道工厂（StreamBridge.statsChannel / groupsChannel）
 * 与订阅者（StatsSubscriber / GroupsSubscriber）。
 */
class StreamWireTest {

    // --- 夹具 ---------------------------------------------------------------

    private fun resource(name: String): String =
        (javaClass.classLoader!!.getResourceAsStream(name) ?: error("找不到夹具 $name（kernel/testdata/wire 应是 test resources）"))
            .readBytes().toString(Charsets.UTF_8)

    private val groupsFirst get() = resource("groups-first.json")
    private val statsFrame get() = resource("stats-frame.json")

    private val goldenDir = File("../../kernel/testdata/wire")
    private val updateGolden = System.getenv("UPDATE_GOLDEN") == "1"

    // --- 记录型 BinaryMessenger：真实 EventChannel 注册 handler、经它发出信封 --------

    private class RecordingMessenger : BinaryMessenger {
        val handlers = LinkedHashMap<String, BinaryMessenger.BinaryMessageHandler>()
        val sent = ArrayList<Pair<String, ByteArray>>()

        override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            sent += channel to bytesOf(message)
        }

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (handler == null) handlers.remove(channel) else handlers[channel] = handler
        }

        /** 像 Dart 一样向通道投递一个方法调用（listen / cancel），返回应答字节。 */
        fun call(channel: String, encoded: ByteBuffer): ByteArray {
            var reply: ByteArray? = null
            // 与引擎交接消息的方式一致：编码器返回的缓冲区「已写入的长度 = position」，接收方拿到的是 [0, position) 那一段
            handlers.getValue(channel).onMessage(ByteBuffer.wrap(bytesOf(encoded))) { reply = bytesOf(it) }
            return reply ?: error("handler 没有应答")
        }

        companion object {
            /** Flutter 的编解码器返回的缓冲区，有效内容是 [0, position)。 */
            fun bytesOf(b: ByteBuffer?): ByteArray {
                if (b == null) return ByteArray(0)
                val d = b.duplicate()
                val n = d.position()
                d.rewind()
                return ByteArray(n).also { d.get(it) }
            }
        }
    }

    private class CapturingSink : EventChannel.EventSink {
        val events = ArrayList<Any?>()
        override fun success(event: Any?) {
            events += event
        }

        override fun error(code: String?, message: String?, details: Any?) = error("unexpected error event $code")
        override fun endOfStream() = Unit
    }

    /** 经生产代码的通道工厂建 EventChannel、listen 之后拿到真实的 sink（会把事件编成信封交给 messenger.sent）。 */
    private class Wired(val messenger: RecordingMessenger, val channelName: String, val sink: EventChannel.EventSink)

    private fun wireStats(): Wired {
        val m = RecordingMessenger()
        var captured: EventChannel.EventSink? = null
        StreamBridge.statsChannel(m).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                captured = events
            }

            override fun onCancel(arguments: Any?) = Unit
        })
        val name = m.handlers.keys.single()
        m.call(name, JSONMethodCodec.INSTANCE.encodeMethodCall(MethodCall("listen", null)))
        return Wired(m, name, captured ?: error("listen 之后没有拿到 sink"))
    }

    private fun wireGroups(): Wired {
        val m = RecordingMessenger()
        var captured: EventChannel.EventSink? = null
        StreamBridge.groupsChannel(m).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                captured = events
            }

            override fun onCancel(arguments: Any?) = Unit
        })
        val name = m.handlers.keys.single()
        m.call(name, StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall("listen", null)))
        return Wired(m, name, captured ?: error("listen 之后没有拿到 sink"))
    }

    // --- 值层：订阅者发到 sink 的是什么类型 ---------------------------------------

    @Test
    fun `分组 到 sink 的值是内核给的同一个 String`() {
        val sink = CapturingSink()
        val json = groupsFirst
        GroupsSubscriber(sink).onGroups(json)
        assertEquals(1, sink.events.size)
        assertTrue("分组必须是 String，而不是解析后的结构", sink.events[0] is String)
        assertSame("原样透传，不重新编码", json, sink.events[0])
    }

    @Test
    fun `统计 到 sink 的值是 Map 而不是 String 六个键齐全 数值与夹具一致`() {
        val sink = CapturingSink()
        StatsSubscriber(sink).onStats(statsFrame)
        assertEquals(1, sink.events.size)
        val v = sink.events[0]
        assertFalse("统计发成字符串，Dart 会静默当成全零（BoxStats.empty）", v is String)
        assertTrue(v is Map<*, *>)
        val map = v as Map<*, *>
        assertEquals(
            listOf("connections-in", "connections-out", "uplink", "downlink", "uplink-total", "downlink-total"),
            map.keys.toList(),
        )
        val fixture = JSONObject(statsFrame)
        for ((k, value) in map) {
            assertTrue("$k 应是 Long，实际 ${value?.javaClass}", value is Long)
            assertEquals(fixture.getLong(k as String), value)
        }
        assertEquals(3L, map["connections-in"])
        assertEquals(8_388_608L, map["downlink-total"])
    }

    @Test
    fun `畸形统计帧被丢弃 不崩溃 不向 Dart 发出半截数据`() {
        for (bad in listOf("not json", "{}", """{"connections-in":1}""", """{"uplink":"fast"}""")) {
            val sink = CapturingSink()
            StatsSubscriber(sink).onStats(bad)
            assertEquals("丢弃：$bad", 0, sink.events.size)
        }
    }

    // --- 信封层：经真实通道与 codec 编出的字节 ------------------------------------

    private fun statsEnvelopeText(w: Wired): String {
        assertEquals(1, w.messenger.sent.size)
        assertEquals(w.channelName, w.messenger.sent[0].first)
        return w.messenger.sent[0].second.toString(Charsets.UTF_8)
    }

    @Test
    fun `统计信封 与黄金文件逐字节一致（JSONMethodCodec）`() {
        val w = wireStats()
        assertEquals("com.clashmiao.app/stats", w.channelName)
        StatsSubscriber(w.sink).onStats(statsFrame)
        val text = statsEnvelopeText(w)
        val golden = File(goldenDir, "stats-envelope.json")
        if (updateGolden) golden.writeText(text)
        assertEquals("信封黄金文件 stats-envelope.json 过期（UPDATE_GOLDEN=1 重写并评审 diff）", golden.readText(), text)
        // 信封里的 payload 是对象，不是被字符串化的对象
        val payload = org.json.JSONArray(text).get(0)
        assertTrue("统计信封的载荷必须是 JSON 对象: $text", payload is JSONObject)
    }

    @Test
    fun `分组信封 与黄金文件逐字节一致（Standard codec）`() {
        val w = wireGroups()
        assertEquals("com.clashmiao.app/groups", w.channelName)
        GroupsSubscriber(w.sink).onGroups(groupsFirst)
        assertEquals(1, w.messenger.sent.size)
        assertEquals(w.channelName, w.messenger.sent[0].first)
        val bytes = w.messenger.sent[0].second
        val b64 = Base64.getEncoder().encodeToString(bytes)
        val golden = File(goldenDir, "groups-envelope.b64")
        if (updateGolden) golden.writeText(b64 + "\n")
        assertEquals("信封黄金文件 groups-envelope.b64 过期（UPDATE_GOLDEN=1 重写并评审 diff）", golden.readText().trim(), b64)
        // 解回来：成功信封，值是原来的 JSON 字符串
        val decoded = StandardMethodCodec.INSTANCE.decodeEnvelope(ByteBuffer.wrap(bytes))
        assertEquals(groupsFirst, decoded)
    }

    @Test
    fun `反例 把统计当字符串发 信封与黄金文件不同 测试必须抓住`() {
        val w = wireStats()
        // 故意走错的路：把 Go 给的 JSON 文本原样发出（旧实现里「把统计透传成字符串」的错误形态）
        w.sink.success(statsFrame)
        val wrong = statsEnvelopeText(w)
        val golden = File(goldenDir, "stats-envelope.json").readText()
        assertNotEquals("字符串信封不能与对象信封相同", golden, wrong)
        val payload = org.json.JSONArray(wrong).get(0)
        assertTrue("字符串被编成 JSON 字符串: $wrong", payload is String)
        assertFalse(payload is JSONObject)
    }

    @Test
    fun `通道编码确实是分组 Standard 与统计 JSON 两种不同的 codec`() {
        // 统计信封是 JSON 文本，分组信封是二进制（首字节 0 = 成功）
        val s = wireStats()
        StatsSubscriber(s.sink).onStats(statsFrame)
        assertEquals('['.code.toByte(), s.messenger.sent[0].second[0])
        val g = wireGroups()
        GroupsSubscriber(g.sink).onGroups(groupsFirst)
        assertArrayEquals(byteArrayOf(0), g.messenger.sent[0].second.copyOf(1))
    }
}
