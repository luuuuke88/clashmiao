package com.clashmiao.clashmiao

import android.content.Intent
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.lifecycleScope
import com.clashmiao.clashmiao.bridge.MethodBridge
import com.clashmiao.clashmiao.bridge.PigeonBridge
import com.clashmiao.clashmiao.bridge.ServiceEvent
import com.clashmiao.clashmiao.bridge.StreamBridge
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.EngineMode
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.engine.KernelConnection
import com.clashmiao.clashmiao.engine.LogBuffer
import com.clashmiao.clashmiao.engine.PermissionGate
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Flutter 入口 Activity，主要职责四件：
 *   1. 注册 Flutter↔Native 的 [MethodBridge] / [StreamBridge] / [PigeonBridge]
 *   2. 通过 [KernelConnection] 跟后台 service 绑 / 解绑
 *   3. 通过 [PermissionGate] 拉 VPN + 通知权限 dialog
 *   4. 把 [LogBuffer] / [serviceStatus] / [serviceAlerts] LiveData 暴露给 StreamBridge
 *
 * 真正的 sing-box 内核逻辑 / 路由 / TUN 设置在 [engine.KernelHost] / [engine.TunnelService]
 * 里，跟 Activity 完全解耦。
 */
class MainActivity : FlutterFragmentActivity(),
    KernelConnection.Sink,
    PermissionGate.Listener {

    companion object {
        lateinit var instance: MainActivity
            private set
    }

    private val connection = KernelConnection(this, this)
    private val permissionGate = PermissionGate(this)

    val logBuffer = LogBuffer(capacity = 300)
    val serviceStatus = MutableLiveData(KernelStatus.Stopped)
    val serviceAlerts = MutableLiveData<ServiceEvent?>(null)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        permissionGate.bindActivity(this)
        // Android 13+ 通知权限：故意放在这里（跟 startService()/VPN 连接流程完全
        // 无关的一次性 Activity 初始化点），而不是塞进 startService()。原因见
        // startService() 上的注释——通知权限不是连接前置条件。这里调用不阻塞：
        // askNotificationPermissionIfNeeded() 非 suspend，只是 fire-and-forget 地
        // 弹系统权限 dialog（或在低版本 / 已授权时直接返回），结果异步走
        // onNotificationConsented/onNotificationDenied 回调。
        permissionGate.askNotificationPermissionIfNeeded()
        connection.resetBinding()
        // 三层 plugin：Dart→native RPC、native→Dart push streams、Pigeon 强类型迁移中。
        flutterEngine.plugins.add(MethodBridge(lifecycleScope))
        flutterEngine.plugins.add(StreamBridge().also { it.installScope(lifecycleScope) })
        flutterEngine.plugins.add(PigeonBridge(lifecycleScope))
    }

    // === 给 KernelHost / 内部 caller 用的入口 =============================

    fun reconnect() = connection.resetBinding()

    /**
     * 启动 sing-box service：
     *   1. 如果当前 mode 是 VPN，确保有 VPN 授权（首次弹 system consent）
     *   2. 权限检查完成后，按 mode 决定 startForegroundService([Prefs.Engine.serviceClass]())
     *
     * POST_NOTIFICATIONS 不能作为连接前置条件：Android 13+ 允许前台服务在通知
     * 权限未授予时启动，只是通知不会展示在通知抽屉里。连接时弹通知权限会打断
     * VPN 启动链路，甚至让 Dart 端长期停在 BoxStarting。
     */
    fun startService() {
        lifecycleScope.launch(Dispatchers.IO) {
            if (Prefs.Engine.shouldRebuildService()) reconnect()
            if (Prefs.Engine.mode == EngineMode.VPN) {
                val ready = withContext(Dispatchers.Main) {
                    permissionGate.askVpnPermissionIfNeeded()
                }
                if (!ready) return@launch // 等 user 在 system dialog 上选
            }
            launchForegroundServiceNow()
        }
    }

    private suspend fun launchForegroundServiceNow() = withContext(Dispatchers.Main) {
        val intent = Intent(Application.application, Prefs.Engine.serviceClass())
        ContextCompat.startForegroundService(Application.application, intent)
    }

    // === KernelConnection.Sink ============================================

    override fun onStatusChange(status: KernelStatus) = serviceStatus.postValue(status)

    override fun onAlert(code: AlertCode, message: String?) =
        serviceAlerts.postValue(ServiceEvent(KernelStatus.Stopped, code, message))

    override fun onWriteLog(message: String?) {
        message ?: return
        logBuffer.append(message)
    }

    override fun onResetLogs(messages: MutableList<String>) = logBuffer.reset(messages)

    // === PermissionGate.Listener ==========================================
    // VPN 授权完成重试 startService，让正常路径继续；VPN/通知被拒绝都走 alert 通知 UI。
    // 通知授权不是任何功能的前置条件（没有它前台服务照常启动，只是通知不展示），
    // 所以 onNotificationConsented 没有像 onVpnConsented 那样需要重试的动作。

    override fun onVpnConsented() = startService()
    override fun onVpnDenied() = onAlert(AlertCode.RequestVPNPermission, null)
    override fun onNotificationConsented() = Unit
    override fun onNotificationDenied() = onAlert(AlertCode.RequestNotificationPermission, null)
    override fun onPreflightFailure(code: AlertCode, message: String?) = onAlert(code, message)

    // === Activity 生命周期 ================================================

    override fun onDestroy() {
        permissionGate.unbindActivity()
        connection.disconnect()
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
