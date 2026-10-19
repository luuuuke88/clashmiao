package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * VPN 授权对话框归属：每个对话框一个唯一 requestCode，结果按它只报告给弹出它的 token；
 * 宿主重建不覆盖旧对话框的归属；新请求在对话框关闭后自己重新检查。
 */
class VpnConsentBrokerTest {

    private var consented = false

    /** 弹出的对话框：(宿主, requestCode)。 */
    private val dialogs = ArrayList<Pair<Any, Int>>()
    private val results = ArrayList<Triple<Long, Boolean, String>>()
    private val host = Any()

    private val broker = VpnConsentBroker<String, Any>(
        prepare = { if (consented) null else "intent" },
        launch = { h, _, code -> dialogs += h to code },
        sink = { t, g, m -> results += Triple(t, g, m) },
    )

    private fun code(i: Int) = dialogs[i].second

    @Test
    fun `已授权直接通过 不弹窗`() {
        consented = true
        broker.attach(host)
        broker.request(1)
        assertEquals(listOf(Triple(1L, true, "")), results)
        assertEquals(0, dialogs.size)
    }

    @Test
    fun `没有界面时如实失败`() {
        broker.request(1)
        assertEquals(1, results.size)
        assertEquals(false, results.single().second)
    }

    @Test
    fun `分配单调递增从不重复 不论结果是否返回`() {
        broker.attach(host)
        val n = 600 // 远超旧实现的 32 项淘汰与 256 槽回绕
        repeat(n) { i ->
            broker.request(i.toLong())
            if (i % 2 == 0) broker.onResult(code(i), false) // 一半返回、一半永远不返回
            else broker.detach(host).also { broker.attach(host) }
        }
        val codes = dialogs.map { it.second }
        assertEquals("$n 个对话框 $n 个不同标识", n, codes.toSet().size)
        assertEquals("严格单调", codes.sorted(), codes)
        assertTrue(codes.all { VpnConsentBroker.owns(it) && it <= 0xFFFF })
        assertEquals(VpnConsentBroker.REQUEST_CODE_BASE, codes.first())
        assertFalse(VpnConsentBroker.owns(PermissionGate.REQ_VPN))
        assertFalse(VpnConsentBroker.owns(PermissionGate.REQ_NOTIFICATION))
    }

    @Test
    fun `大量未返回的弹窗加宿主重建 旧拒绝与旧同意迟到都只报给各自的旧 token`() {
        var h: Any = host
        broker.attach(h)
        val n = 300
        repeat(n) { i ->
            broker.request(i.toLong()) // 弹窗后宿主被销毁重建，结果始终没回来
            broker.detach(h)
            h = Any()
            broker.attach(h)
        }
        broker.request(9_999L) // 最新请求
        val newest = code(n)
        assertEquals(n + 1, dialogs.size)
        // 最早的旧拒绝、中间的旧同意迟到
        assertTrue(broker.onResult(code(0), false))
        assertTrue(broker.onResult(code(255), true))
        assertTrue(broker.onResult(code(256), false))
        assertEquals(
            listOf(
                Triple(0L, false, "user denied vpn consent"),
                Triple(255L, true, ""),
                Triple(256L, false, "user denied vpn consent"),
            ),
            results,
        )
        assertTrue("最新请求没有被任何旧结果终结", results.none { it.first == 9_999L })
        broker.onResult(newest, true)
        assertEquals(Triple(9_999L, true, ""), results.last())
    }

    @Test
    fun `标识用尽 需要弹窗的请求以独立消息 permissionDenied 已授权仍直接通过`() {
        val limited = VpnConsentBroker<String, Any>(
            prepare = { if (consented) null else "intent" },
            launch = { h, _, code -> dialogs += h to code },
            sink = { t, g, m -> results += Triple(t, g, m) },
            codeLimit = VpnConsentBroker.REQUEST_CODE_BASE + 3,
        )
        limited.attach(host)
        repeat(3) { i ->
            limited.request(i.toLong())
            limited.detach(host)
            limited.attach(host) // 结果永远不回
        }
        assertEquals(3, dialogs.size)
        limited.request(10)
        assertEquals("不再弹窗、不复用旧标识", 3, dialogs.size)
        assertEquals(Triple(10L, false, VpnConsentBroker.EXHAUSTED_MESSAGE), results.last())
        // 已授权：无需对话框，照常通过
        consented = true
        limited.request(11)
        assertEquals(Triple(11L, true, ""), results.last())
        // 迟到的旧结果仍只归旧 token
        consented = false
        limited.onResult(dialogs[0].second, false)
        assertEquals(Triple(0L, false, "user denied vpn consent"), results.last())
    }

    @Test
    fun `弹窗期间的新 token 不重复弹窗 结果只报给弹出它的 token 新 token 关窗后重新检查`() {
        broker.attach(host)
        broker.request(1)
        assertEquals(1, dialogs.size)
        broker.cancel(1) // off
        broker.request(2) // 新 on
        assertEquals("不重复弹窗", 1, dialogs.size)
        consented = true
        assertTrue(broker.onResult(code(0), true))
        assertEquals(listOf(Triple(1L, true, ""), Triple(2L, true, "")), results)
    }

    @Test
    fun `旧弹窗被拒 只把拒绝报给旧 token 仍需授权的新 token 为自己重新弹窗`() {
        broker.attach(host)
        broker.request(1)
        broker.cancel(1)
        broker.request(2)
        broker.onResult(code(0), false)
        assertEquals(listOf(Triple(1L, false, "user denied vpn consent")), results)
        assertEquals(2, dialogs.size)
        broker.onResult(code(1), true)
        assertEquals(Triple(2L, true, ""), results.last())
    }

    @Test
    fun `被撤销的挂起 token 关窗后不再检查`() {
        broker.attach(host)
        broker.request(1)
        broker.request(2)
        broker.cancel(2)
        broker.onResult(code(0), true)
        assertEquals(listOf(Triple(1L, true, "")), results)
    }

    @Test
    fun `宿主重建后新请求弹新对话框 旧对话框结果迟到仍只报给旧 token`() {
        broker.attach(host)
        broker.request(1)
        broker.detach(host)
        val recreated = Any()
        broker.attach(recreated)
        broker.request(2)
        assertEquals(2, dialogs.size)
        assertTrue(dialogs[1].first === recreated)
        // 旧对话框的同意迟到
        broker.onResult(code(0), true)
        assertEquals(listOf(Triple(1L, true, "")), results)
        // 新对话框仍开着：之后的请求挂起，等它关闭
        broker.request(3)
        assertEquals(2, dialogs.size)
        broker.onResult(code(1), false)
        assertEquals(Triple(2L, false, "user denied vpn consent"), results[1])
        assertEquals("token 3 关窗后重新检查、弹自己的对话框", 3, dialogs.size)
    }

    @Test
    fun `宿主重建后旧对话框的拒绝迟到 不影响新对话框`() {
        broker.attach(host)
        broker.request(1)
        broker.detach(host)
        broker.attach(Any())
        broker.request(2)
        broker.onResult(code(0), false)
        assertEquals(listOf(Triple(1L, false, "user denied vpn consent")), results)
        consented = true
        broker.onResult(code(1), true)
        assertEquals(Triple(2L, true, ""), results.last())
    }

    @Test
    fun `重复或陌生的 requestCode 被忽略`() {
        broker.attach(host)
        broker.request(1)
        broker.onResult(code(0), true)
        assertTrue(broker.onResult(code(0), false))
        assertFalse(broker.onResult(44, false))
        assertEquals(listOf(Triple(1L, true, "")), results)
    }
}
