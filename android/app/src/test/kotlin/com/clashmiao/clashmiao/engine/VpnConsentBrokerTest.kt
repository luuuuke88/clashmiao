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
    fun `每个对话框的 requestCode 唯一且落在保留区间`() {
        broker.attach(host)
        val codes = HashSet<Int>()
        repeat(40) { i ->
            broker.request(i.toLong())
            codes += code(i)
            assertTrue(VpnConsentBroker.owns(code(i)))
            broker.onResult(code(i), false)
        }
        assertEquals("40 个对话框 40 个不同标识", 40, codes.size)
        assertFalse(VpnConsentBroker.owns(PermissionGate.REQ_VPN))
        assertFalse(VpnConsentBroker.owns(PermissionGate.REQ_NOTIFICATION))
        assertTrue(code(0) <= 0xFFFF)
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
