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
 *   2. 通过 [PermissionGate] 拉通知权限 dialog；VPN 授权对话框由进程级 [KernelCoordinator]
 *      分配唯一 requestCode，结果按它交回、只归弹出它的请求（过期的授权回调会被协调器丢弃）
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

    override fun launchVpnConsent(intent: Intent, requestCode: Int) {
        // 每个对话框一个唯一 requestCode（协调器分配）：结果按它归属，Activity 重建也不会认错对话框。
        startActivityForResult(intent, requestCode)
    }

    // === PermissionGate.Listener ==========================================
    // VPN 授权由协调器按 requestCode 归属（见 onActivityResult），不经 PermissionGate 的固定 REQ_VPN；
    // 通知权限被拒走非生命周期 alert，通知授权不是任何功能的前置条件。

    override fun onVpnConsented() = Unit
    override fun onVpnDenied() = Unit
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
        if (KernelCoordinator.onVpnConsentResult(requestCode, resultCode == RESULT_OK)) return
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
