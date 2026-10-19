package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Test

/** VPN 授权对话框归属：结果只报告给弹出它的 token，新请求在对话框关闭后自己重新检查。 */
class VpnConsentBrokerTest {

    private var consented = false
    private val dialogs = ArrayList<Long>()
    private val results = ArrayList<Triple<Long, Boolean, String>>()
    private var pendingLaunch: Long? = null
    private val host = Any()

    private val broker = VpnConsentBroker<String, Any>(
        prepare = { if (consented) null else "intent" },
        launch = { _, _ -> dialogs += pendingLaunch ?: -1 },
        sink = { t, g, m -> results += Triple(t, g, m) },
    )

    private fun request(token: Long) {
        pendingLaunch = token
        broker.request(token)
    }

    @Test
    fun `已授权直接通过 不弹窗`() {
        consented = true
        broker.attach(host)
        request(1)
        assertEquals(listOf(Triple(1L, true, "")), results)
        assertEquals(0, dialogs.size)
    }

    @Test
    fun `没有界面时如实失败`() {
        request(1)
        assertEquals(1, results.size)
        assertEquals(false, results.single().second)
    }

    @Test
    fun `弹窗期间的新 token 不重复弹窗 结果只报给弹出它的 token 新 token 关窗后重新检查`() {
        broker.attach(host)
        request(1)
        assertEquals(listOf(1L), dialogs)
        broker.cancel(1) // off
        request(2) // 新 on
        assertEquals("不重复弹窗", listOf(1L), dialogs)
        consented = true
        broker.onResult(true)
        assertEquals(listOf(Triple(1L, true, ""), Triple(2L, true, "")), results)
    }

    @Test
    fun `旧弹窗被拒 只把拒绝报给旧 token 仍需授权的新 token 为自己重新弹窗`() {
        broker.attach(host)
        request(1)
        broker.cancel(1)
        request(2)
        broker.onResult(false)
        assertEquals(listOf(Triple(1L, false, "user denied vpn consent")), results)
        assertEquals(2, dialogs.size)
        broker.onResult(true)
        assertEquals(Triple(2L, true, ""), results.last())
    }

    @Test
    fun `被撤销的挂起 token 关窗后不再检查`() {
        broker.attach(host)
        request(1)
        request(2)
        broker.cancel(2)
        broker.onResult(true)
        assertEquals(listOf(Triple(1L, true, "")), results)
    }

    @Test
    fun `界面销毁后不再挡住新请求`() {
        broker.attach(host)
        request(1)
        broker.detach(host)
        val other = Any()
        broker.attach(other)
        request(2)
        assertEquals(2, dialogs.size)
    }
}
