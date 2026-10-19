package com.clashmiao.clashmiao.engine

/**
 * VPN 授权对话框的归属（spec §3「VPN 授权」、§10.2）。纯 Kotlin，JVM 可测；
 * [AndroidCoordinatorPlatform] 以进程级单例持有它，用 `VpnService.prepare` 与 Activity 实例化。
 *
 * **每个对话框一个唯一标识**：弹窗时从保留区间 [REQUEST_CODE_BASE, REQUEST_CODE_BASE + REQUEST_CODE_SPAN)
 * 里分配一个 requestCode，`startActivityForResult` 带着它，结果经 onActivityResult 原样带回；
 * 本类（进程级，不在 Activity 里）保存 requestCode → 弹出它的 token 的映射。所以：
 *  - 结果**只**报告给弹出该对话框的 token，绝不改交后来的请求（协调器核心再丢弃过期 token）；
 *  - Activity 销毁 / 重建不会覆盖旧对话框的归属：重建后新请求弹的是新标识的新对话框，
 *    旧对话框的结果迟到时仍按它自己的标识找到原 token；
 *  - 对话框开着时到达的新 token 先挂起，当前对话框关闭后各自**重新检查**授权
 *    （已授权直接通过，仍需授权就为它弹新对话框）。
 *
 * 只在主线程调用。
 *
 * @param prepare 返回 null = 已授权；否则返回需要启动的授权界面（可能抛异常）。
 * @param launch 在界面宿主上以给定 requestCode 弹出授权对话框（可能抛异常）。
 * @param sink 授权结果（token, granted, message）。
 */
class VpnConsentBroker<I : Any, H : Any>(
    private val prepare: () -> I?,
    private val launch: (host: H, intent: I, requestCode: Int) -> Unit,
    private val sink: (token: Long, granted: Boolean, message: String) -> Unit,
) {
    companion object {
        /** 授权对话框专用的 requestCode 区间（与 PermissionGate / MethodBridge 的固定值不重叠，且 ≤ 0xFFFF）。 */
        const val REQUEST_CODE_BASE = 0x5100
        const val REQUEST_CODE_SPAN = 0x100

        /** 结果始终不来的旧对话框最多记这么多个（最旧的先丢）。 */
        private const val MAX_TRACKED = 32

        fun owns(requestCode: Int): Boolean =
            requestCode >= REQUEST_CODE_BASE && requestCode < REQUEST_CODE_BASE + REQUEST_CODE_SPAN
    }

    private var host: H? = null
    private var nextSlot = 0

    /** requestCode → 弹出该对话框的 token（插入序 = 弹出序）。 */
    private val dialogs = LinkedHashMap<Int, Long>()

    /** 当前宿主上正在显示、挡住新弹窗的对话框；宿主销毁后为空（它的归属仍留在 [dialogs]）。 */
    private var openCode: Int? = null

    /** 对话框开着时到达、等它关闭后重新检查的 token。 */
    private val deferred = LinkedHashSet<Long>()

    fun request(token: Long) {
        if (openCode != null) {
            deferred += token
            return
        }
        check(token)
    }

    /**
     * 撤销 token 的等待。已经弹出的对话框不受影响：它关闭时结果仍报告给弹出它的 token
     * （由核心丢弃），从不转交给别的请求。
     */
    fun cancel(token: Long) {
        deferred -= token
    }

    /**
     * 对话框结果（Activity.onActivityResult）。返回 false = 不是本类分配的 requestCode。
     * 结果只按 [requestCode] 找原 token；不认识的（已被淘汰的）标识直接忽略。
     */
    fun onResult(requestCode: Int, granted: Boolean): Boolean {
        if (!owns(requestCode)) return false
        val token = dialogs.remove(requestCode)
        if (openCode == requestCode) openCode = null
        if (token != null) sink(token, granted, if (granted) "" else "user denied vpn consent")
        recheckDeferred()
        return true
    }

    fun attach(h: H) {
        host = h
    }

    fun detach(h: H) {
        if (host !== h) return
        host = null
        // 界面没了：不再挡住之后的新请求（新请求弹新标识的对话框）；旧对话框的归属保留在映射里，
        // 它的结果若随重建后的 Activity 迟到，仍报告给它自己的 token。
        openCode = null
    }

    private fun recheckDeferred() {
        while (openCode == null && deferred.isNotEmpty()) {
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
        val code = allocate()
        dialogs[code] = token
        openCode = code
        try {
            launch(h, intent, code)
        } catch (e: Exception) {
            dialogs.remove(code)
            openCode = null
            sink(token, false, e.message ?: "cannot show vpn consent")
        }
    }

    private fun allocate(): Int {
        while (dialogs.size >= MAX_TRACKED) dialogs.remove(dialogs.keys.first())
        var code: Int
        do {
            code = REQUEST_CODE_BASE + nextSlot
            nextSlot = (nextSlot + 1) % REQUEST_CODE_SPAN
        } while (dialogs.containsKey(code))
        return code
    }
}
