package com.clashmiao.clashmiao

import android.content.Intent
import androidx.lifecycle.lifecycleScope
import com.clashmiao.clashmiao.bridge.MethodBridge
import com.clashmiao.clashmiao.bridge.PigeonBridge
import com.clashmiao.clashmiao.bridge.StreamBridge
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.engine.ActivityHost
import com.clashmiao.clashmiao.engine.KernelCoordinator
import com.clashmiao.clashmiao.engine.PermissionGate
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Flutter 入口 Activity，只有三件事：
 *   1. 注册 Flutter↔Native 的 [MethodBridge] / [StreamBridge] / [PigeonBridge]
 *   2. 通过 [PermissionGate] 拉 VPN 授权 + 通知权限 dialog，并把 VPN 授权结果交给进程级
 *      [KernelCoordinator] 按「当前意图」校验（过期的授权回调会被协调器丢弃）
 *   3. 作为 [ActivityHost] 向协调器暴露「能弹授权窗」这一能力
 *
 * 连接状态、日志缓冲、内核生命周期全部归协调器；Activity 不持有状态镜像，也不再绑定 Service，
 * 更没有静态 Activity 引用（旧的 `MainActivity.instance` 会泄漏已销毁的 Activity）。
 */
class MainActivity : FlutterFragmentActivity(),
    PermissionGate.Listener,
    ActivityHost {

    private val permissionGate = PermissionGate(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        permissionGate.bindActivity(this)
        KernelCoordinator.attachActivity(this)
        // Android 13+ 通知权限：故意放在这里（跟连接流程完全无关的一次性 Activity 初始化点）。
        // 通知权限不是连接前置条件——没有它前台服务照常启动，只是通知不展示。
        permissionGate.askNotificationPermissionIfNeeded()
        // 三层 plugin：Dart→native RPC、native→Dart push streams、Pigeon 强类型。
        flutterEngine.plugins.add(MethodBridge(lifecycleScope))
        flutterEngine.plugins.add(StreamBridge().also { it.installScope(lifecycleScope) })
        flutterEngine.plugins.add(PigeonBridge(lifecycleScope))
    }

    // === ActivityHost ======================================================

    override fun launchVpnConsent(intent: Intent) {
        startActivityForResult(intent, PermissionGate.REQ_VPN)
    }

    // === PermissionGate.Listener ==========================================
    // VPN 授权结果交协调器；通知权限被拒走非生命周期 alert，通知授权不是任何功能的前置条件。

    override fun onVpnConsented() = KernelCoordinator.onVpnConsentResult(true)
    override fun onVpnDenied() = KernelCoordinator.onVpnConsentResult(false)
    override fun onNotificationConsented() = Unit
    override fun onNotificationDenied() =
        KernelCoordinator.instance.emitAlert(AlertCode.RequestNotificationPermission, null)

    override fun onPreflightFailure(code: AlertCode, message: String?) =
        KernelCoordinator.instance.emitAlert(code, message)

    // === Activity 生命周期 ================================================

    override fun onDestroy() {
        permissionGate.unbindActivity()
        KernelCoordinator.detachActivity(this)
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        permissionGate.handleActivityResult(requestCode, resultCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        permissionGate.handleRequestPermissionsResult(requestCode, grantResults)
    }
}
