package com.clashmiao.clashmiao.engine

import android.app.Activity
import android.content.pm.PackageManager
import com.clashmiao.clashmiao.core.AlertCode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 这里只测 dispatch / decode 这层 —— [PermissionGate.handleActivityResult]
 * 和 [PermissionGate.handleRequestPermissionsResult]。这两个不需要 Activity
 * 实例，只是 int code → listener 调度，host JVM 跑得动。
 *
 * `askXxxPermissionIfNeeded()` 这两条会真的调 Android framework，要 Robolectric
 * 或 instrumented test 覆盖，留给后续。
 */
class PermissionGateTest {

    private class RecordingListener : PermissionGate.Listener {
        var vpnConsented = 0
        var vpnDenied = 0
        var notiConsented = 0
        var notiDenied = 0
        var preflightFailures = mutableListOf<Pair<AlertCode, String?>>()

        override fun onVpnConsented() {
            vpnConsented++
        }

        override fun onVpnDenied() {
            vpnDenied++
        }

        override fun onNotificationConsented() {
            notiConsented++
        }

        override fun onNotificationDenied() {
            notiDenied++
        }

        override fun onPreflightFailure(code: AlertCode, message: String?) {
            preflightFailures += code to message
        }
    }

    private fun newGate(listener: PermissionGate.Listener = RecordingListener()) =
        PermissionGate(listener)

    // === handleActivityResult VPN consent =================================

    @Test
    fun `handleActivityResult REQ_VPN RESULT_OK 触发 onVpnConsented`() {
        val l = RecordingListener()
        val consumed = newGate(l).handleActivityResult(
            PermissionGate.REQ_VPN,
            Activity.RESULT_OK,
        )
        assertTrue(consumed)
        assertEquals(1, l.vpnConsented)
        assertEquals(0, l.vpnDenied)
    }

    @Test
    fun `handleActivityResult REQ_VPN RESULT_CANCELED 触发 onVpnDenied`() {
        val l = RecordingListener()
        val consumed = newGate(l).handleActivityResult(
            PermissionGate.REQ_VPN,
            Activity.RESULT_CANCELED,
        )
        assertTrue(consumed)
        assertEquals(0, l.vpnConsented)
        assertEquals(1, l.vpnDenied)
    }

    @Test
    fun `handleActivityResult REQ_NOTIFICATION RESULT_OK 触发 onNotificationConsented`() {
        val l = RecordingListener()
        newGate(l).handleActivityResult(
            PermissionGate.REQ_NOTIFICATION,
            Activity.RESULT_OK,
        )
        assertEquals(1, l.notiConsented)
        assertEquals(0, l.notiDenied)
    }

    @Test
    fun `handleActivityResult 其它 requestCode 返回 false（不消费）`() {
        val l = RecordingListener()
        val consumed = newGate(l).handleActivityResult(
            requestCode = 9999,
            resultCode = Activity.RESULT_OK,
        )
        assertFalse(consumed)
        assertEquals(0, l.vpnConsented)
        assertEquals(0, l.notiConsented)
    }

    // === handleRequestPermissionsResult ===================================

    @Test
    fun `handleRequestPermissionsResult GRANTED 触发 onNotificationConsented`() {
        val l = RecordingListener()
        val consumed = newGate(l).handleRequestPermissionsResult(
            PermissionGate.REQ_NOTIFICATION,
            intArrayOf(PackageManager.PERMISSION_GRANTED),
        )
        assertTrue(consumed)
        assertEquals(1, l.notiConsented)
        assertEquals(0, l.notiDenied)
    }

    @Test
    fun `handleRequestPermissionsResult DENIED 触发 onNotificationDenied`() {
        val l = RecordingListener()
        newGate(l).handleRequestPermissionsResult(
            PermissionGate.REQ_NOTIFICATION,
            intArrayOf(PackageManager.PERMISSION_DENIED),
        )
        assertEquals(0, l.notiConsented)
        assertEquals(1, l.notiDenied)
    }

    @Test
    fun `handleRequestPermissionsResult 空 grantResults 当作 denied`() {
        val l = RecordingListener()
        newGate(l).handleRequestPermissionsResult(
            PermissionGate.REQ_NOTIFICATION,
            intArrayOf(),
        )
        // 应该走 denied 分支（grantResults.isNotEmpty() 判 false）
        assertEquals(1, l.notiDenied)
    }

    @Test
    fun `handleRequestPermissionsResult 其它 requestCode 返回 false`() {
        val l = RecordingListener()
        val consumed = newGate(l).handleRequestPermissionsResult(
            requestCode = 9999,
            grantResults = intArrayOf(PackageManager.PERMISSION_GRANTED),
        )
        assertFalse(consumed)
        assertEquals(0, l.notiConsented)
    }
}
