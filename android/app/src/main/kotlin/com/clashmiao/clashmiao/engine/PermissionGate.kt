package com.clashmiao.clashmiao.engine

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import androidx.core.app.ActivityCompat
import com.clashmiao.clashmiao.core.AlertCode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 把 VPN 权限 + POST_NOTIFICATIONS（Android 13+）的申请 + onActivityResult /
 * onRequestPermissionsResult 回调那一坨 boilerplate 抽出 Activity 主体。
 *
 * Activity 这边只需要：
 *   1. 在 [bindActivity] 里把自己注入进来
 *   2. 在 [onActivityResult] / [onRequestPermissionsResult] 回调里转手给本类的
 *      [handleActivityResult] / [handleRequestPermissionsResult]
 *   3. 调 [askVpnPermissionIfNeeded] / [askNotificationPermissionIfNeeded]
 *      触发实际申请；用户决定结果通过 [Listener] 回调
 *
 * 写成 class（不是 object）是因为它持有 Activity 引用，跟 Activity 同生命周期。
 */
class PermissionGate(private val listener: Listener) {

    interface Listener {
        fun onVpnConsented()
        fun onVpnDenied()
        fun onNotificationConsented()
        fun onNotificationDenied()
        /** 弹申请之前 throw 了（VpnService.prepare 偶尔会抛 SecurityException 之类）。 */
        fun onPreflightFailure(code: AlertCode, message: String?)
    }

    companion object {
        const val REQ_VPN = 1001
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
     * 检查并申请 VPN 权限。
     * @return `true` 表示已经有权限 / 不需要弹（可以直接走 startService）；
     *         `false` 表示弹了 system dialog，等 [handleActivityResult] 回调
     */
    suspend fun askVpnPermissionIfNeeded(): Boolean = withContext(Dispatchers.Main) {
        val act = activity ?: return@withContext false
        try {
            val pendingIntent = VpnService.prepare(act)
            if (pendingIntent == null) {
                true
            } else {
                act.startActivityForResult(pendingIntent, REQ_VPN)
                false
            }
        } catch (e: Exception) {
            listener.onPreflightFailure(AlertCode.RequestVPNPermission, e.message)
            false
        }
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

    // === Activity 转手回来的 callback ====================================

    /** Activity.onActivityResult 把 result code 转发到这里。返回 true 表示这个 requestCode 我们消费了。 */
    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean = when (requestCode) {
        REQ_VPN -> {
            if (resultCode == Activity.RESULT_OK) listener.onVpnConsented()
            else listener.onVpnDenied()
            true
        }
        REQ_NOTIFICATION -> {
            // 老版 OS 用 startActivityForResult 走这一支；新版走 handleRequestPermissionsResult
            if (resultCode == Activity.RESULT_OK) listener.onNotificationConsented()
            else listener.onNotificationDenied()
            true
        }
        else -> false
    }

    fun handleRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQ_NOTIFICATION) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) listener.onNotificationConsented() else listener.onNotificationDenied()
        return true
    }
}
