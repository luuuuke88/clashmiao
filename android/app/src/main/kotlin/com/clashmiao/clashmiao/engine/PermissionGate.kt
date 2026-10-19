package com.clashmiao.clashmiao.engine

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat

/**
 * POST_NOTIFICATIONS（Android 13+）的申请 + onRequestPermissionsResult 回调，从 Activity
 * 主体里抽出来。
 *
 * VPN 授权不在这里：它由进程级 [KernelCoordinator] 经 [VpnConsentBroker] 为每个对话框分配
 * 唯一 requestCode，结果只归弹出它的请求。
 *
 * Activity 这边只需要：
 *   1. 在 [bindActivity] 里把自己注入进来
 *   2. 在 onRequestPermissionsResult 回调里转手给 [handleRequestPermissionsResult]
 *   3. 调 [askNotificationPermissionIfNeeded] 触发实际申请；用户决定结果通过 [Listener] 回调
 *
 * 写成 class（不是 object）是因为它持有 Activity 引用，跟 Activity 同生命周期。
 */
class PermissionGate(private val listener: Listener) {

    interface Listener {
        fun onNotificationConsented()
        fun onNotificationDenied()
    }

    companion object {
        const val REQ_NOTIFICATION = 1010
    }

    private var activity: Activity? = null

    fun bindActivity(a: Activity) {
        activity = a
    }

    fun unbindActivity() {
        activity = null
    }

    /**
     * Tiramisu+ 上申请 POST_NOTIFICATIONS。低版本永远 [true]（隐式拥有权限）。
     */
    fun askNotificationPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val act = activity ?: return false
        ActivityCompat.requestPermissions(
            act,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_NOTIFICATION,
        )
        return false
    }

    /** Activity.onRequestPermissionsResult 转发到这里。返回 true 表示这个 requestCode 我们消费了。 */
    fun handleRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_NOTIFICATION) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) listener.onNotificationConsented() else listener.onNotificationDenied()
        return true
    }
}
