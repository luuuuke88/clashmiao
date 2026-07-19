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
import org.json.JSONArray
import org.json.JSONObject
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
    @Volatile private var reloading = false

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
            }.withoutRuntimeUrlTestOutbounds()

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
        if (reloading) return
        reloading = true
        statusLive.postValue(KernelStatus.Starting)
        GlobalScope.launch(Dispatchers.IO) {
            try {
                withContext(Dispatchers.Main) { notice.close() }
                closeTunFd()
                commandServer?.setService(null)
                teardownLibboxService()
                launchKernel(retryAfter = 1000L)
            } finally {
                reloading = false
            }
        }
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
            teardownRuntime()
            Prefs.Engine.startedByUser = false
            withContext(Dispatchers.Main) {
                statusLive.value = KernelStatus.Stopped
                service.stopSelf()
            }
        }
    }

    private suspend fun abortWithAlert(code: AlertCode, message: String? = null) {
        Prefs.Engine.startedByUser = false
        // 启动失败必须像 shutdown() 一样把运行时资源拆干净。tun 可能已在 start()
        // 中途 establish()（见 TunnelService.openTun）接管了全设备流量，若只复位
        // 状态而不关 tunFd / teardown libbox，就遗弃了一个孤儿 tun —— 设备黑洞
        // 断网，且每次失败重试各泄漏一个。调用上下文与 shutdown() 保持一致：
        // teardownRuntime() 跑在 IO（本 suspend 由 onStartCommand 的 IO 协程驱动），
        // UI 相关的事仍在 Main。
        teardownRuntime()
        withContext(Dispatchers.Main) {
            unregisterControlReceiver()
            notice.close()
            binder.fanOut { it.onServiceAlert(code.ordinal, message) }
            statusLive.value = KernelStatus.Stopped
            // 这是"启动失败"而非用户主动停止，Service 组件不能继续无通知地挂着
            // （参照 shutdown() 的 stopSelf）。
            service.stopSelf()
        }
    }

    private fun unregisterControlReceiver() {
        if (!receiverRegistered) return
        runCatching { service.unregisterReceiver(controlReceiver) }
        receiverRegistered = false
    }

    /**
     * 拆除内核运行时资源：关闭 Android 侧原始 tun fd（撤销系统路由表）、断开
     * command server 与 libbox service 的绑定、销毁 libbox service、注销本地
     * DNS transport、disarm 默认网络监听、彻底关闭 command server 自身（native
     * 引用一并 destroy）。
     *
     * [shutdown]（用户主动停止）与 [abortWithAlert]（启动失败兜底）共用这一整段，
     * 消除"某个终结路径又漏了清理"的类别性风险——历史上 abortWithAlert 先是漏了
     * tun fd / libbox service 这三件事（导致 tun 在 start() 中途 establish() 后
     * 被原地遗弃、设备黑洞断网），后来这里补上前三件事之后，才发现 abort 仍然漏了
     * 后三件事（DNS transport 注销 / NetworkWatcher disarm / commandServer 自身
     * 关闭），导致启动失败重试时每次泄漏一个 CommandServer 的 native 资源
     * （goroutine / fd / Seq ref），直到进程死亡才被系统回收。现在两条终结路径
     * 都只经这一个函数收口，六件事逐字与旧 shutdown() 顺序一致。
     *
     * 因为 [NetworkWatcher.disarm] 是 suspend fun，这里整体升级成 suspend；跑在
     * 调用方的协程上下文里（shutdown / abortWithAlert 均为 IO）。
     *
     * 安全性：launchKernel() 里最早的 abort 触发点（EmptyConfiguration，配置路径
     * / options 为空或 buildConfig 失败）发生在 [NetworkWatcher.arm] 和
     * `Libbox.registerLocalDNSTransport(SystemDnsBridge)` **之前**，此时 watcher
     * 未 arm、DNS transport 未注册成 non-null。下面每个动作在这种"提前 abort"下
     * 都必须是 null-safe / 幂等 no-op：
     *   - [closeTunFd] / [teardownLibboxService]：内部先取字段，为 null 直接
     *     return，不做任何事。
     *   - `commandServer?.setService(null)` / `commandServer?.apply { ... }`：
     *     safe-call，commandServer 为 null（如尚未 spawnCommandServer 成功）时
     *     整个表达式跳过；commandServer 非 null 时，close() 前总是先经过本函数
     *     前面的 `setService(null)`，所以无论走 shutdown 还是任一 abort 分支，
     *     close() 看到的 commandServer 内部状态（service 引用已清空）都相同，
     *     不存在"abort 独有的未定义状态"。
     *   - `Libbox.registerLocalDNSTransport(null)`：单参数 setter 语义（把全局
     *     transport 指针设成给定值），传 null 覆盖"从未注册过"的默认状态是幂等
     *     操作，不依赖调用前是否曾经 non-null 过。
     *   - [NetworkWatcher.disarm]：`actor.send(Op.Unsubscribe(watcherKey))` ->
     *     `subs.remove(op.key)`；key 从未 subscribe（[NetworkWatcher.arm] 没被
     *     调过）时 remove 返回 null，`had=false`，直接跳过 `unregister()`，是
     *     纯粹的 no-op，不抛异常。
     */
    private suspend fun teardownRuntime() {
        closeTunFd()
        commandServer?.setService(null)
        teardownLibboxService()
        // 每个原生清理各自 runCatching 兜底：任一步抛异常（尤其闭源 libbox 的
        // registerLocalDNSTransport、或 CommandServer.close）都不得中断后续清理，
        // 更不能让调用方在 teardown 之后的 statusLive=Stopped / stopSelf / alert
        // 收不了尾——那正是本函数要消除的"清理级联失败"。与 closeTunFd /
        // teardownLibboxService 内部已有的 runCatching 保持一致。commandServer = null
        // 是纯字段赋值不会抛，留在 runCatching 外，保证任何情况下都置空。
        runCatching { Libbox.registerLocalDNSTransport(null) }
        runCatching { NetworkWatcher.disarm() }
        runCatching {
            commandServer?.apply {
                close()
                Seq.destroyRef(refnum)
            }
        }
        commandServer = null
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

    private fun String.withoutRuntimeUrlTestOutbounds(): String {
        return try {
            val root = JSONObject(this)
            val outbounds = root.optJSONArray("outbounds") ?: return this
            val removedTags = mutableSetOf<String>()
            val kept = JSONArray()
            for (i in 0 until outbounds.length()) {
                val outbound = outbounds.optJSONObject(i)
                if (outbound == null) {
                    kept.put(outbounds.get(i))
                    continue
                }
                val type = outbound.optString("type")
                if (type == "urltest" || type == "url_test") {
                    outbound.optString("tag").takeIf { it.isNotBlank() }?.let(removedTags::add)
                    continue
                }
                kept.put(outbound)
            }
            if (removedTags.isEmpty()) return this

            val tagTypes = mutableMapOf<String, String>()
            for (i in 0 until kept.length()) {
                val outbound = kept.optJSONObject(i) ?: continue
                val tag = outbound.optString("tag")
                val type = outbound.optString("type")
                if (tag.isNotBlank() && type.isNotBlank()) tagTypes[tag] = type
            }

            fun isLeafProxy(tag: String): Boolean {
                return when (tagTypes[tag]) {
                    null, "direct", "dns", "block", "selector", "urltest", "url_test" -> false
                    else -> true
                }
            }

            val proxyTags = mutableListOf<String>()
            for (i in 0 until kept.length()) {
                val outbound = kept.optJSONObject(i) ?: continue
                val tag = outbound.optString("tag")
                if (tag.isNotBlank() && isLeafProxy(tag)) proxyTags.add(tag)
            }

        var hasUsableProxySelector = false
        var hasUsableSelector = false
        var proxySelector: JSONObject? = null
        for (i in 0 until kept.length()) {
            val outbound = kept.optJSONObject(i) ?: continue
            if (outbound.optString("type") != "selector") continue
            if (outbound.optString("tag") == "proxy") proxySelector = outbound

            val current = outbound.optJSONArray("outbounds")
            val cleanedTags = mutableListOf<String>()
            if (current != null) {
                for (j in 0 until current.length()) {
                        val tag = current.optString(j)
                        if (tag.isNotBlank() && isLeafProxy(tag)) cleanedTags.add(tag)
                    }
                }
                val effectiveTags = if (cleanedTags.isNotEmpty()) cleanedTags else proxyTags
                outbound.put("outbounds", JSONArray(effectiveTags))
                val defaultTag = outbound.optString("default")
                if (effectiveTags.isNotEmpty() && defaultTag !in effectiveTags) {
                    outbound.put("default", effectiveTags.first())
                }
                if (effectiveTags.isNotEmpty()) {
                    hasUsableSelector = true
                if (outbound.optString("tag") == "proxy") hasUsableProxySelector = true
            }
        }

        if (proxyTags.isNotEmpty() && proxySelector != null) {
            proxySelector.put("outbounds", JSONArray(proxyTags))
            val defaultTag = proxySelector.optString("default")
            if (defaultTag !in proxyTags) proxySelector.put("default", proxyTags.first())
            hasUsableSelector = true
            hasUsableProxySelector = true
        } else if (proxyTags.isNotEmpty()) {
            kept.put(
                JSONObject()
                    .put("type", "selector")
                    .put("tag", "proxy")
                    .put("outbounds", JSONArray(proxyTags))
                    .put("default", proxyTags.first()),
            )
            hasUsableSelector = true
            hasUsableProxySelector = true
            tagTypes["proxy"] = "selector"
        }

            val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
            val finalTag = route.optString("final")
            val finalType = tagTypes[finalTag]
            if (finalTag.isBlank() ||
                finalTag in removedTags ||
                finalType == null ||
                finalType == "urltest" ||
                finalType == "url_test"
            ) {
                val fallback = when {
                    hasUsableProxySelector -> "proxy"
                    hasUsableSelector -> firstSelectorTag(kept)
                    proxyTags.isNotEmpty() -> proxyTags.first()
                    tagTypes.containsKey("direct") -> "direct"
                    else -> finalTag
                }
                if (fallback.isNotBlank()) route.put("final", fallback)
            }

            root.put("outbounds", kept)
            Log.d(TAG, "removed runtime urltest outbounds: ${removedTags.joinToString()}")
            root.toString()
        } catch (e: Exception) {
            Log.w(TAG, "failed to sanitize runtime config", e)
            this
        }
    }

    private fun firstSelectorTag(outbounds: JSONArray): String {
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            if (outbound.optString("type") == "selector") {
                return outbound.optString("tag")
            }
        }
        return ""
    }
}
