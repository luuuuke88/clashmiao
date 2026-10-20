package com.clashmiao.clashmiao.engine

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.clashmiao.clashmiao.R
import com.clashmiao.clashmiao.core.BroadcastIntents
import com.clashmiao.libcore.core.Platform
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 一个 Android Service 实例（[TunnelService] 或 [PlainService]）与进程级 [KernelCoordinator] 之间的
 * 薄适配层。Service 把 onStartCommand / onDestroy / onRevoke 委托到这里，这里只做三件事：
 *
 *   1. **生命周期上报**：onStartCommand 先 `startForeground`（Android 14+ 要求 ~5 s 内），
 *      再把 startId 交给协调器；onDestroy / onRevoke 同样只是上报事件，**不做阻塞操作**
 *      （旧实现的 onRevoke 在主线程 runBlocking 等主线程，会 ANR）。
 *   2. **按实例暴露给协调器的能力**：运行时（[CoreKernelRuntime]）、通知更新、
 *      `stopSelfResult(startId)`。是否启动、何时停、何时退休全部由协调器决定。
 *   3. **转发实例级广播**：通知栏「停止」按钮 → 协调器外部请求（source=notification）；
 *      旧 RELOAD 广播 → 重载请求（source=system）；Doze 进出 → 运行时暂停/唤醒。
 */
@OptIn(DelicateCoroutinesApi::class)
class KernelHost(
    private val service: Service,
    override val type: ServiceType,
    platform: Platform,
) : ServiceHandle {

    private companion object {
        const val TAG = "engine/KernelHost"
    }

    private val coordinator get() = KernelCoordinator.instance

    override val id: Int = coordinator.nextInstanceId()

    private val notice = ForegroundNotice(service)

    private val runtime = CoreKernelRuntime(
        service = service,
        platform = platform,
        logs = coordinator.logs,
        onReloadRequested = { coordinator.onReloadRequested(Source.System) },
    )

    override val kernelRuntime: KernelRuntime get() = runtime

    /** TunnelService.openTun 建好的 FD；归 runtime 所有，teardown 时关闭。 */
    var tunFd: ParcelFileDescriptor?
        get() = runtime.tunFd
        set(value) {
            runtime.tunFd = value
        }

    /** 当前一代动态通知的启动任务；停止 / 销毁时取消（代际复查在 [ForegroundNotice] 内）。 */
    private var noticeJob: Job? = null

    private var receiverRegistered = false
    private var noticeProfile = ""
    private var noticeStatusRes = R.string.status_starting

    private val controlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BroadcastIntents.SHUTDOWN -> coordinator.external(Source.Notification, Desired.Off)
                BroadcastIntents.RELOAD -> coordinator.onReloadRequested(Source.System)
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) runtime.onIdleModeChanged()
            }
        }
    }

    // === Android Service callbacks ========================================

    fun onStartCommand(@Suppress("UNUSED_PARAMETER") intent: Intent?, flags: Int, startId: Int): Int {
        // Android 14+ 要求 onStartCommand 后 ~5s 内必须 startForeground，否则
        // ForegroundServiceDidNotStartInTimeException：无论协调器稍后怎么决定，先挂上通知。
        // 已经有内核在跑时（异常的重复 start 命令）沿用当前文案，不倒退成「启动中」。
        showNotice(noticeProfile, noticeStatusRes)
        registerControlReceiver()
        Log.d(TAG, "onStartCommand instance=$id startId=$startId flags=$flags")
        coordinator.onServiceStarted(this, startId)
        return Service.START_NOT_STICKY
    }

    fun onDestroy() {
        Log.d(TAG, "onDestroy instance=$id")
        unregisterControlReceiver()
        cancelNoticeJob()
        runCatching { notice.close() }
        coordinator.onServiceDestroyed(this)
    }

    fun onRevoke() {
        Log.d(TAG, "onRevoke instance=$id")
        coordinator.onServiceRevoked(this)
    }

    /** 内核通过 [CorePlatform.writeLog] 回调进来的日志，直接写进进程级缓冲。 */
    fun writeLog(message: String) {
        coordinator.logs.append(message)
    }

    // === ServiceHandle ======================================================

    override fun stopSelfResult(startId: Int): Boolean = service.stopSelfResult(startId)

    override fun noticeStarting(profileName: String) = showNotice(profileName, R.string.status_starting)

    override fun noticeStarted(profileName: String) {
        showNotice(profileName, R.string.status_started)
        cancelNoticeJob()
        val generation = notice.beginUpdates()
        noticeJob = GlobalScope.launch(Dispatchers.IO) { notice.startUpdates(generation) }
    }

    override fun noticeStopUpdates() {
        cancelNoticeJob()
        notice.stopUpdates()
    }

    private fun cancelNoticeJob() {
        noticeJob?.cancel()
        noticeJob = null
    }

    // === 内部 ===============================================================

    private fun showNotice(profileName: String, statusRes: Int) {
        noticeProfile = profileName
        noticeStatusRes = statusRes
        try {
            notice.show(profileName, statusRes)
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed", e)
        }
    }

    private fun registerControlReceiver() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            service,
            controlReceiver,
            IntentFilter().apply {
                addAction(BroadcastIntents.SHUTDOWN)
                addAction(BroadcastIntents.RELOAD)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                }
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    private fun unregisterControlReceiver() {
        if (!receiverRegistered) return
        runCatching { service.unregisterReceiver(controlReceiver) }
        receiverRegistered = false
    }
}
