package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.Cidr
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Go 一侧拍平的 TUN 规格（spec §4.3）在宿主侧的解析。 */
class TunSpecTest {

    // spec §4.3 的示例（合成数据）
    private val example = """
        {"mtu":9000,"auto_route":true,"strict_route":true,"dns_mode":"hijack",
         "dns_servers":["172.19.0.2"],
         "inet4_address":["172.19.0.1/28"],"inet6_address":[],
         "inet4_route":[],"inet6_route":[],"inet4_route_exclude":[],"inet6_route_exclude":[],
         "inet4_route_range":["0.0.0.0/1","128.0.0.0/1"],"inet6_route_range":[],
         "include_package":[],"exclude_package":[],
         "http_proxy":{"enabled":false,"server":"","port":0,"bypass":[],"match":[]}}
    """.trimIndent()

    @Test
    fun `spec 示例 JSON 逐字段解析`() {
        val s = TunSpec.parse(example)
        assertEquals(9000, s.mtu)
        assertTrue(s.autoRoute)
        assertTrue(s.strictRoute)
        assertEquals(TunSpec.DnsMode.Hijack, s.dnsMode)
        assertEquals(listOf("172.19.0.2"), s.dnsServers)
        assertEquals(listOf(Cidr("172.19.0.1", 28)), s.inet4Address)
        assertEquals(emptyList<Cidr>(), s.inet6Address)
        assertEquals(listOf(Cidr("0.0.0.0", 1), Cidr("128.0.0.0", 1)), s.inet4RouteRange)
        assertEquals(emptyList<Cidr>(), s.inet4Route)
        assertEquals(emptyList<String>(), s.includePackage)
        assertFalse(s.httpProxy.enabled)
    }

    @Test
    fun `dns_mode 三态与缺省`() {
        fun mode(json: String) = TunSpec.parse(json).dnsMode
        assertEquals(TunSpec.DnsMode.Disabled, mode("""{"dns_mode":"disabled"}"""))
        assertEquals(TunSpec.DnsMode.Native, mode("""{"dns_mode":"native"}"""))
        assertEquals(TunSpec.DnsMode.Hijack, mode("""{"dns_mode":"hijack"}"""))
        // 缺省 / 空串 / 未知值：内核默认行为是 hijack
        assertEquals(TunSpec.DnsMode.Hijack, mode("{}"))
        assertEquals(TunSpec.DnsMode.Hijack, mode("""{"dns_mode":""}"""))
        assertEquals(TunSpec.DnsMode.Hijack, mode("""{"dns_mode":"future-mode"}"""))
    }

    @Test
    fun `缺字段容错 空对象解析成全空的规格`() {
        val s = TunSpec.parse("{}")
        assertEquals(0, s.mtu)
        assertFalse(s.autoRoute)
        assertEquals(emptyList<String>(), s.dnsServers)
        assertEquals(emptyList<Cidr>(), s.inet4Address)
        assertEquals(TunSpec.HttpProxy.Disabled, s.httpProxy)
    }

    @Test
    fun `未知的新键被忽略`() {
        val s = TunSpec.parse("""{"mtu":1500,"x_future":[1,2,3]}""")
        assertEquals(1500, s.mtu)
    }

    @Test
    fun `HTTP 代理 启用时带出服务器端口与匹配列表`() {
        val s = TunSpec.parse(
            """{"http_proxy":{"enabled":true,"server":"127.0.0.1","port":2080,"bypass":["*.lan"],"match":["example.net"]}}""",
        )
        assertTrue(s.httpProxy.enabled)
        assertEquals("127.0.0.1", s.httpProxy.server)
        assertEquals(2080, s.httpProxy.port)
        assertEquals(listOf("*.lan"), s.httpProxy.bypass)
        assertEquals(listOf("example.net"), s.httpProxy.match)
    }

    @Test
    fun `IPv6 地址与前缀`() {
        val s = TunSpec.parse("""{"inet6_address":["fdfe:dcba:9876::1/126"],"inet6_route_exclude":["2001:db8::/32"]}""")
        assertEquals(listOf(Cidr("fdfe:dcba:9876::1", 126)), s.inet6Address)
        assertEquals(listOf(Cidr("2001:db8::", 32)), s.inet6RouteExclude)
    }

    @Test
    fun `不是 JSON 或 CIDR 不合法 抛参数异常`() {
        for (bad in listOf("not json", "[]", """{"inet4_address":["172.19.0.1"]}""", """{"inet4_address":["172.19.0.1/99"]}""", """{"inet6_address":["::1/200"]}""", """{"inet4_route":["a/b"]}""")) {
            try {
                TunSpec.parse(bad)
                fail("应当拒绝：$bad")
            } catch (_: IllegalArgumentException) {
            }
        }
    }

    @Test
    fun `Cidr 文本往返`() {
        assertEquals("10.0.0.1/8", Cidr.parse("10.0.0.1/8").toString())
        assertEquals(Cidr("::", 0), Cidr.parse("::/0"))
    }
}
