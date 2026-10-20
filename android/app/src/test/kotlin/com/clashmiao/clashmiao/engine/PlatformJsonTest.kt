package com.clashmiao.clashmiao.engine

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** 平台回调的 JSON 载荷：键名是与 Go 一侧（engine/platform.go 的 ownerJSON / ifaceJSON）约定的契约。 */
class PlatformJsonTest {

    @Test
    fun `连接归属载荷`() {
        val o = JSONObject(PlatformJson.owner(10123, listOf("com.example.a", "com.example.b")))
        assertEquals(setOf("uid", "packages"), o.keys().asSequence().toSet())
        assertEquals(10123, o.getInt("uid"))
        assertEquals(listOf("com.example.a", "com.example.b"), o.getJSONArray("packages").toList())
        // 没有包名（系统 uid）也是合法载荷
        assertEquals(0, JSONObject(PlatformJson.owner(0, emptyList())).getJSONArray("packages").length())
    }

    @Test
    fun `接口列表载荷键集合与取值`() {
        val json = PlatformJson.interfaces(
            listOf(
                PlatformJson.Iface(
                    name = "wlan0", index = 21, mtu = 1500, flags = 0x1043, type = PlatformJson.TYPE_WIFI,
                    addresses = listOf("192.0.2.10/24", "2001:db8::10/64"), dns = listOf("192.0.2.1"),
                    gateway = emptyList(), metered = false,
                ),
                PlatformJson.Iface("rmnet0", 22, 1400, 0, PlatformJson.TYPE_CELLULAR, emptyList(), emptyList(), emptyList(), true),
            ),
        )
        val arr = JSONArray(json)
        assertEquals(2, arr.length())
        val wlan = arr.getJSONObject(0)
        assertEquals(
            setOf("name", "index", "mtu", "flags", "type", "addresses", "dns", "gateway", "metered"),
            wlan.keys().asSequence().toSet(),
        )
        assertEquals("wlan0", wlan.getString("name"))
        assertEquals(21, wlan.getInt("index"))
        assertEquals(listOf("192.0.2.10/24", "2001:db8::10/64"), wlan.getJSONArray("addresses").toList())
        assertEquals(listOf("192.0.2.1"), wlan.getJSONArray("dns").toList())
        assertFalse(wlan.getBoolean("metered"))
        assertTrue(arr.getJSONObject(1).getBoolean("metered"))
        assertEquals(PlatformJson.TYPE_CELLULAR, arr.getJSONObject(1).getInt("type"))
    }

    @Test
    fun `空列表是合法的空数组`() {
        assertEquals("[]", PlatformJson.interfaces(emptyList()))
    }

    @Test
    fun `接口类型按传输方式优先级归类`() {
        assertEquals(PlatformJson.TYPE_WIFI, PlatformJson.typeOf(wifi = true, cellular = true, ethernet = false))
        assertEquals(PlatformJson.TYPE_CELLULAR, PlatformJson.typeOf(wifi = false, cellular = true, ethernet = true))
        assertEquals(PlatformJson.TYPE_ETHERNET, PlatformJson.typeOf(wifi = false, cellular = false, ethernet = true))
        assertEquals(PlatformJson.TYPE_OTHER, PlatformJson.typeOf(wifi = false, cellular = false, ethernet = false))
    }

    private fun JSONArray.toList(): List<String> = (0 until length()).map { getString(it) }
}
