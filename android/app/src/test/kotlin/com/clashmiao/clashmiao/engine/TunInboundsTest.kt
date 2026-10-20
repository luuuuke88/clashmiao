package com.clashmiao.clashmiao.engine

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/** 真机验收 BUG-B：最终运行配置里多于一个 tun inbound 时只留内核 append 的最后一个。 */
class TunInboundsTest {

    private fun types(content: String): List<String> {
        val arr = JSONObject(content).getJSONArray("inbounds")
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            "${o.getString("type")}:${o.optString("tag")}:${o.optInt("mtu")}"
        }
    }

    @Test
    fun `两个 tun inbound 只留最后一个 其余 inbound 与顺序不变`() {
        val content = """
            {"log":{},"inbounds":[
              {"type":"tun","tag":"tun-in","mtu":9000,"stack":"mixed"},
              {"type":"socks","tag":"s","mtu":0},
              {"type":"tun","tag":"tun-in","mtu":1500,"stack":"system"},
              {"type":"mixed","tag":"mixed-in","mtu":0}
            ],"outbounds":[{"type":"direct","tag":"direct"}]}
        """.trimIndent()

        val r = TunInbounds.keepLast(content)

        assertEquals(1, r.removed)
        assertEquals(listOf("socks:s:0", "tun:tun-in:1500", "mixed:mixed-in:0"), types(r.content))
        assertEquals("direct", JSONObject(r.content).getJSONArray("outbounds").getJSONObject(0).getString("tag"))
    }

    @Test
    fun `至多一个 tun 或没有 inbounds 或不是 JSON 原样返回`() {
        for (c in listOf(
            """{"inbounds":[{"type":"tun"},{"type":"mixed"}]}""",
            """{"inbounds":[{"type":"mixed"}]}""",
            """{"outbounds":[]}""",
            "cfg",
        )) {
            val r = TunInbounds.keepLast(c)
            assertEquals(c, 0, r.removed)
            assertSame(c, c, r.content)
        }
    }
}
