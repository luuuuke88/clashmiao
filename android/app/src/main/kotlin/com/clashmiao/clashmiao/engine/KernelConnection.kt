package com.clashmiao.clashmiao.engine

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.RemoteException
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.clashmiao.clashmiao.IService
import com.clashmiao.clashmiao.IServiceCallback
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.BroadcastIntents
import com.clashmiao.clashmiao.core.KernelStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Activity 端的 bind-service 代理：根据当前 EngineMode 选 TunnelService 或
 * PlainService 来 bind，把 service 推过来的 status / alert / log 转发给 [Sink]。
 *
 * 重新设计的点 vs 老 ServiceConnection.kt：
 *   - "Sink" 接口名替代了原本含糊的 "Callback"
 *   - service 类查询通过 [Prefs.Engine.serviceClass] 在 IO 线程跑，绑定本身在 main
 *   - [resetBinding] 替代原本 reconnect 名字（避免误以为是网络重连）
 *   - 内部 AIDL → Kotlin enum 的 marshal 逻辑提到顶层 [decodeStatus] /
 *     [decodeAlert]，单测时直接验
 */
class KernelConnection(
    private val ctx: Context,
    sink: Sink,
    private val registerCallback: Boolean = true,
) : ServiceConnection {

    interface Sink {
        fun onStatusChange(status: KernelStatus)
        fun onAlert(code: AlertCode, message: String?) = Unit
        fun onWriteLog(message: String?) = Unit
        fun onResetLogs(messages: MutableList<String>) = Unit
    }

    companion object {
        private const val TAG = "engine/KernelConn"

        @JvmStatic
        fun decodeStatus(ordinal: Int): KernelStatus =
            KernelStatus.values().getOrElse(ordinal) { KernelStatus.Stopped }

        @JvmStatic
        fun decodeAlert(ordinal: Int): AlertCode =
            AlertCode.values().getOrElse(ordinal) { AlertCode.StartService }
    }

    private val callbackProxy = SinkProxy(sink)
    private var bound: IService? = null

    /** 上一次拿到的 status；service 还没 bind 时返回 [KernelStatus.Stopped]。 */
    val lastKnownStatus: KernelStatus
        get() = bound?.status?.let(::decodeStatus) ?: KernelStatus.Stopped

    fun connect() = doBind()

    fun disconnect() = unbindSilently()

    /** 关闭旧绑定 + 重新 bind（mode 切换时用）。 */
    fun resetBinding() {
        unbindSilently()
        doBind()
    }

    private fun doBind() {
        val intent = runBlocking {
            withContext(Dispatchers.IO) {
                Intent(ctx, Prefs.Engine.serviceClass()).setAction(BroadcastIntents.START)
            }
        }
        ctx.bindService(intent, this, AppCompatActivity.BIND_AUTO_CREATE)
    }

    private fun unbindSilently() = runCatching { ctx.unbindService(this) }

    // === ServiceConnection ================================================

    override fun onServiceConnected(name: ComponentName, binder: IBinder) {
        val svc = IService.Stub.asInterface(binder)
        bound = svc
        try {
            if (registerCallback) svc.registerCallback(callbackProxy)
            callbackProxy.onServiceStatusChanged(svc.status)
        } catch (e: RemoteException) {
            Log.e(TAG, "bind callback failed", e)
        }
    }

    override fun onServiceDisconnected(name: ComponentName?) {
        try {
            bound?.unregisterCallback(callbackProxy)
        } catch (e: RemoteException) {
            Log.e(TAG, "unbind callback failed", e)
        }
    }

    override fun onBindingDied(name: ComponentName?) {
        resetBinding()
    }

    // === AIDL ↔ Sink 内部 marshalling layer ================================

    private class SinkProxy(private val sink: Sink) : IServiceCallback.Stub() {
        override fun onServiceStatusChanged(status: Int) =
            sink.onStatusChange(decodeStatus(status))

        override fun onServiceAlert(type: Int, message: String?) =
            sink.onAlert(decodeAlert(type), message)

        override fun onServiceWriteLog(message: String?) = sink.onWriteLog(message)

        override fun onServiceResetLogs(messages: MutableList<String>) =
            sink.onResetLogs(messages)
    }
}
