package com.clashmiao.clashmiao.engine

import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 这里只测 dispatch / decode 这层 —— [PermissionGate.handleRequestPermissionsResult]。
 * 它不需要 Activity 实例，只是 int code → listener 调度，host JVM 跑得动。
 *
 * `askNotificationPermissionIfNeeded()` 会真的调 Android framework，要 Robolectric
 * 或 instrumented test 覆盖，留给后续。VPN 授权不经 PermissionGate（见
 * VpnConsentBrokerTest）。
 */
class PermissionGateTest {

    private class RecordingListener : PermissionGate.Listener {
        var notiConsented = 0
        var notiDenied = 0

        override fun onNotificationConsented() {
            notiConsented++
        }

        override fun onNotificationDenied() {
            notiDenied++
        }
    }

    private fun newGate(listener: PermissionGate.Listener = RecordingListener()) =
        PermissionGate(listener)

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
