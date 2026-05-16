package com.clashmiao.clashmiao.engine

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.R
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.BroadcastIntents
import com.clashmiao.clashmiao.core.KernelStatus
import go.Seq
import io.nekohasekai.libbox.BoxService as LibboxBoxService
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

/**
 * 内核生命周期控制器。一个 Android Service（TunnelService 或 PlainService）持有
 * 一个 [KernelHost]，把 [Service.onStartCommand] / [Service.onBind] / [Service.onDestroy]
 * 委托给这里。
 *
 * GlobalScope 是故意的：sing-box service 跑全局，coroutine 必须在 Activity / Fragment
 * scope 之外存活，否则用户切到后台时进度就被取消了。下面 @OptIn 是给 IDE / lint 看的。
 *
 * @OptIn applies to 整个类（compiler 标记），不影响运行时行为。
 *
 * 内部状态：
 *   - [statusLive] —— 由 [KernelBinder] 镜像出去给所有 AIDL callback；同时也
 *     供 [KernelConnection] 在 activity 端订阅
 *   - [tunFd] —— TunnelService.openTun 建好的 FD，被 sing-box 包到 TUN reader 里。
 *
 * 旧 BoxService 是一坨 357 行的 god class，混了 service-lifecycle / libbox-lifecycle /
 * IPC binder / notification / network monitor / shutdown receiver。这里把 IPC binder
 * 拆到 [KernelBinder]，notification 拆到 [ForegroundNotice]，network monitor 是
 * [NetworkWatcher] 全局 singleton —— KernelHost 只负责"启动 → libbox.newService →
 * 关闭"这条主线。
 */
@OptIn(DelicateCoroutinesApi::class)
class KernelHost(
    private val service: Service,
    private val libbox: PlatformInterface,
) : CommandServerHandler {

    companion object {
        private const val TAG = "engine/KernelHost"

        @Volatile private var initialized = false
        private lateinit var workingDir: File

        /** Libbox.setup 必须只跑一次；多次 setup 会让旧 service 进程残留。 */
        private fun bootstrapOnce() {
            if (initialized) return
            val app = Application.application
            val baseDir = app.filesDir.also { it.mkdirs() }
            workingDir = (app.getExternalFilesDir(null) ?: return).also { it.mkdirs() }
            val tempDir = app.cacheDir.also { it.mkdirs() }
            Log.d(TAG, "libbox dirs base=${baseDir.path} working=${workingDir.path}")
            Libbox.setup(baseDir.path, workingDir.path, tempDir.path, false)
            Libbox.redirectStderr(File(workingDir, "stderr.log").path)
            initialized = true
        }

        /** sing-box config 文本解析（companion 暴露给 ChannelRouter 直接调）。 */
        fun parseConfig(path: String, tempPath: String, debug: Boolean): String = try {
            Mobile.parse(path, tempPath, debug)
            ""
        } catch (e: Exception) {
            Log.w(TAG, "parseConfig failed", e)
            e.message ?: "invalid config"
        }

        /** 拼最终运行用 config（profile + ConfigOptions JSON）。 */
        fun buildConfig(path: String, options: String): String =
            Mobile.buildConfig(path, options)

        /** 启动当前选中 service-mode 的 service。 */
        fun fireStart() {
            val intent = runBlocking {
                withContext(Dispatchers.IO) {
                    Intent(Application.application, Prefs.Engine.serviceClass())
                }
            }
            ContextCompat.startForegroundService(Application.application, intent)
        }

        fun fireStop() {
            Application.application.sendBroadcast(
                Intent(BroadcastIntents.SHUTDOWN).setPackage(Application.application.packageName),
            )
        }

        fun fireReload() {
            Application.application.sendBroadcast(
                Intent(BroadcastIntents.RELOAD).setPackage(Application.application.packageName),
            )
        }
    }

    // === 外部可见状态 + IPC fan-out ========================================

    val statusLive = MutableLiveData(KernelStatus.Stopped)
    private val binder = KernelBinder(statusLive)
    private val notice = ForegroundNotice(service)

    // === 内核进程态 ========================================================

    var tunFd: ParcelFileDescriptor? = null

    private var libboxService: LibboxBoxService? = null
    private var commandServer: CommandServer? = null
    private var profileName = ""
    private var receiverRegistered = false

    private val controlReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BroadcastIntents.SHUTDOWN -> shutdown()
                BroadcastIntents.RELOAD -> serviceReload()
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) toggleIdleMode()
            }
        }
    }

    // === Android Service callbacks ========================================

    fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (statusLive.value != KernelStatus.Stopped) return Service.START_NOT_STICKY
        statusLive.value = KernelStatus.Starting

        // Android 14+ 要求 onStartCommand 后 ~5s 内必须 startForeground，否则
        // ForegroundServiceDidNotStartInTimeException。先挂个空 "starting" 通知占位，
        // 真正的 libbox 启动跑在 IO 协程。
        notice.show("", R.string.status_starting)

        if (!receiverRegistered) {
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

        GlobalScope.launch(Dispatchers.IO) {
            Prefs.Engine.startedByUser = true
            bootstrapOnce()
            try {
                spawnCommandServer()
            } catch (e: Exception) {
                abortWithAlert(AlertCode.StartCommandServer, e.message)
                return@launch
            }
            launchKernel()
        }
        return Service.START_NOT_STICKY
    }

    fun onBind(intent: Intent): IBinder = binder

    fun onDestroy() {
        binder.close()
    }

    fun onRevoke() {
        shutdown()
    }

    /** 让 service 类（TunnelService/PlainService）通过 [KernelHost] 写日志到 IPC。 */
    fun writeLog(message: String) {
        binder.fanOut { it.onServiceWriteLog(message) }
    }

    // === core launch / shutdown ===========================================

    private suspend fun launchKernel(retryAfter: Long = 0L) {
        try {
            val configPath = Prefs.Profile.activeConfigPath
            if (configPath.isBlank()) return abortWithAlert(AlertCode.EmptyConfiguration)

            profileName = Prefs.Profile.activeName
            val options = Prefs.Engine.configOptionsJson
            if (options.isBlank()) return abortWithAlert(AlertCode.EmptyConfiguration)

            val content = try {
                Mobile.buildConfig(configPath, options)
            } catch (e: Exception) {
                Log.w(TAG, "buildConfig failed", e)
                return abortWithAlert(AlertCode.EmptyConfiguration)
            }

            if (Prefs.Engine.debugMode) {
                File(workingDir, "current-config.json").writeText(content)
            }

            // logs 在 reload / start 的时候清一次，让 UI 从干净状态开始。
            withContext(Dispatchers.Main) {
                binder.fanOut { it.onServiceResetLogs(mutableListOf()) }
            }

            NetworkWatcher.arm()
            Libbox.registerLocalDNSTransport(SystemDnsBridge)
            Libbox.setMemoryLimit(!Prefs.Engine.disableMemoryLimit)

            val freshService = try {
                Libbox.newService(content, libbox)
            } catch (e: Exception) {
                return abortWithAlert(AlertCode.CreateService, e.message)
            }

            if (retryAfter > 0) delay(retryAfter)

            freshService.start()
            libboxService = freshService
            commandServer?.setService(freshService)
            statusLive.postValue(KernelStatus.Started)

            withContext(Dispatchers.Main) {
                notice.show(profileName, R.string.status_started)
            }
            notice.start()
        } catch (e: Exception) {
            abortWithAlert(AlertCode.StartService, e.message)
        }
    }

    private fun spawnCommandServer() {
        commandServer = CommandServer(this, 300).also { it.start() }
    }

    override fun serviceReload() {
        notice.close()
        statusLive.postValue(KernelStatus.Starting)
        closeTunFd()
        commandServer?.setService(null)
        teardownLibboxService()
        runBlocking { launchKernel(retryAfter = 1000L) }
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        val tun = service as? TunnelService ?: return status
        status.available = tun.systemProxyAvailable
        status.enabled = tun.systemProxyEnabled
        return status
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        serviceReload()
    }

    override fun postServiceClose() {
        // Android 端不需要：libbox 关闭由 Service 自己 drive。
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun toggleIdleMode() {
        if (Application.powerManager.isDeviceIdleMode) libboxService?.pause()
        else libboxService?.wake()
    }

    private fun shutdown() {
        if (statusLive.value != KernelStatus.Started) return
        statusLive.value = KernelStatus.Stopping
        unregisterControlReceiver()
        notice.close()

        GlobalScope.launch(Dispatchers.IO) {
            closeTunFd()
            commandServer?.setService(null)
            teardownLibboxService()
            Libbox.registerLocalDNSTransport(null)
            NetworkWatcher.disarm()
            commandServer?.apply {
                close()
                Seq.destroyRef(refnum)
            }
            commandServer = null
            Prefs.Engine.startedByUser = false
            withContext(Dispatchers.Main) {
                statusLive.value = KernelStatus.Stopped
                service.stopSelf()
            }
        }
    }

    private suspend fun abortWithAlert(code: AlertCode, message: String? = null) {
        Prefs.Engine.startedByUser = false
        withContext(Dispatchers.Main) {
            unregisterControlReceiver()
            notice.close()
            binder.fanOut { it.onServiceAlert(code.ordinal, message) }
            statusLive.value = KernelStatus.Stopped
        }
    }

    private fun unregisterControlReceiver() {
        if (!receiverRegistered) return
        runCatching { service.unregisterReceiver(controlReceiver) }
        receiverRegistered = false
    }

    private fun closeTunFd() {
        val fd = tunFd ?: return
        runCatching { fd.close() }
        tunFd = null
    }

    private fun teardownLibboxService() {
        val running = libboxService ?: return
        runCatching { running.close() }.onFailure {
            writeLog("kernel: close error: $it")
        }
        Seq.destroyRef(running.refnum)
        libboxService = null
    }
}
