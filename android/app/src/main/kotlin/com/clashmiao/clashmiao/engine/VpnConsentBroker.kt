package com.clashmiao.clashmiao.engine

/**
 * VPN 授权对话框的归属（spec §3「VPN 授权」、§10.2）。纯 Kotlin，JVM 可测；
 * [AndroidCoordinatorPlatform] 用 `VpnService.prepare` 与 Activity 实例化它。
 *
 * 全局只会有一个授权对话框，它的结果**只**报告给弹出它的 token——绝不改交给后来的请求
 * （协调器核心再判断那个 token 是否仍属于当前请求，过期的直接丢弃）。
 * 对话框开着时到达的新 token 先挂起；对话框关闭后各自**重新检查**授权：
 * 已经授权就直接通过，仍需授权就为它重新弹窗。
 *
 * 只在主线程调用。
 *
 * @param prepare 返回 null = 已授权；否则返回需要启动的授权界面（可能抛异常）。
 * @param launch 在界面宿主上弹出授权对话框（可能抛异常）。
 * @param sink 授权结果（token, granted, message）。
 */
class VpnConsentBroker<I : Any, H : Any>(
    private val prepare: () -> I?,
    private val launch: (host: H, intent: I) -> Unit,
    private val sink: (token: Long, granted: Boolean, message: String) -> Unit,
) {
    private var host: H? = null

    /** 弹出当前对话框的 token；对话框结果只属于它。 */
    private var dialogToken: Long? = null
    private var dialogOpen = false

    /** 对话框开着时到达、等它关闭后重新检查的 token。 */
    private val deferred = LinkedHashSet<Long>()

    fun request(token: Long) {
        if (dialogOpen) {
            deferred += token
            return
        }
        check(token)
    }

    /**
     * 撤销 token 的等待。正在显示的对话框不受影响：它关闭时结果仍报告给弹出它的 token
     * （由核心丢弃），从不转交给别的请求。
     */
    fun cancel(token: Long) {
        deferred -= token
    }

    /** 对话框结果（Activity.onActivityResult → PermissionGate）。 */
    fun onResult(granted: Boolean) {
        val token = dialogToken
        dialogToken = null
        dialogOpen = false
        if (token != null) sink(token, granted, if (granted) "" else "user denied vpn consent")
        recheckDeferred()
    }

    fun attach(h: H) {
        host = h
    }

    fun detach(h: H) {
        if (host !== h) return
        host = null
        // 界面没了，对话框结果可能不会再来：不再挡住之后的新请求。挂起的 token 由各自的启动超时兜底。
        dialogOpen = false
    }

    private fun recheckDeferred() {
        while (!dialogOpen && deferred.isNotEmpty()) {
            val next = deferred.first()
            deferred.remove(next)
            check(next)
        }
    }

    private fun check(token: Long) {
        val intent = try {
            prepare()
        } catch (e: Exception) {
            sink(token, false, e.message ?: "VpnService.prepare failed")
            return
        }
        if (intent == null) {
            sink(token, true, "")
            return
        }
        val h = host
        if (h == null) {
            // 没有界面（磁贴 / 开机）：无法弹授权窗口，如实失败。
            sink(token, false, "vpn consent requires the app UI")
            return
        }
        dialogToken = token
        dialogOpen = true
        try {
            launch(h, intent)
        } catch (e: Exception) {
            dialogOpen = false
            dialogToken = null
            sink(token, false, e.message ?: "cannot show vpn consent")
        }
    }
}
