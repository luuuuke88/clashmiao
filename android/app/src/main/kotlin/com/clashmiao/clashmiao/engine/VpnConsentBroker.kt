package com.clashmiao.clashmiao.engine

/**
 * VPN 授权对话框的归属（spec §3「VPN 授权」、§10.2）。纯 Kotlin，JVM 可测；
 * [AndroidCoordinatorPlatform] 以进程级单例持有它，用 `VpnService.prepare` 与 Activity 实例化。
 *
 * **每个对话框一个唯一标识**：弹窗时从保留区间 [REQUEST_CODE_BASE, REQUEST_CODE_LIMIT) 里**单调**分配
 * 一个 requestCode（进程生命周期内从不回绕、从不复用），`startActivityForResult` 带着它，结果经
 * onActivityResult 原样带回；本类（进程级，不在 Activity 里）保存 requestCode → 弹出它的 token 的映射，
 * 未返回的对话框的映射**永不淘汰**（每一项都是一个真实弹出过的对话框，进程内至多约 4.4 万个）。所以：
 *  - 结果**只**报告给弹出该对话框的 token，绝不改交后来的请求（协调器核心再丢弃过期 token）；
 *  - Activity 销毁 / 重建不会覆盖旧对话框的归属：重建后新请求弹的是新标识的新对话框，
 *    旧对话框的结果迟到时仍按它自己的标识找到原 token；
 *  - 对话框开着时到达的新 token 先挂起，当前对话框关闭后各自**重新检查**授权
 *    （已授权直接通过，仍需授权就为它弹新对话框）；
 *  - 标识用尽（进程内弹过约 4.4 万次授权框）：已授权仍直接通过；需要弹窗的请求如实以
 *    permissionDenied 失败（独立的 [EXHAUSTED_MESSAGE]），绝不复用可能还会收到迟到结果的标识。
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
    /** 分配上限（不含）；只有测试会调小它来走到耗尽路径。 */
    private val codeLimit: Int = REQUEST_CODE_LIMIT,
) {
    companion object {
        /**
         * 授权对话框专用的 requestCode 区间 [REQUEST_CODE_BASE, REQUEST_CODE_LIMIT)：
         * 与 PermissionGate / MethodBridge 的固定值不重叠；上限是 FragmentActivity 允许的 16 位。
         */
        const val REQUEST_CODE_BASE = 0x5100
        const val REQUEST_CODE_LIMIT = 0x10000

        const val EXHAUSTED_MESSAGE = "vpn consent request codes exhausted for this process; restart the app"

        fun owns(requestCode: Int): Boolean =
            requestCode >= REQUEST_CODE_BASE && requestCode < REQUEST_CODE_LIMIT
    }

    private var host: H? = null

    /** 下一个要分配的 requestCode：只增不减，从不回绕。 */
    private var nextCode = REQUEST_CODE_BASE

    /** 尚未返回的对话框：requestCode → 弹出它的 token。只在结果返回时移除，从不淘汰。 */
    private val dialogs = HashMap<Int, Long>()

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
     * 结果只按 [requestCode] 找原 token；已返回过的（重复投递）或从未分配的标识直接忽略。
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
        if (code == null) {
            // 标识用尽：宁可如实失败，也不复用可能还会收到迟到结果的标识。
            sink(token, false, EXHAUSTED_MESSAGE)
            return
        }
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

    /** 单调分配；用尽返回 null。分配过的标识进程内永不再分配（天然的「已退役」标记）。 */
    private fun allocate(): Int? {
        if (nextCode >= codeLimit) return null
        return nextCode++
    }
}
