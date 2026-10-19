package com.clashmiao.clashmiao.engine

import android.app.Service
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.core.Prefs
import go.Seq
import io.nekohasekai.libbox.BoxService as LibboxBoxService
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.runBlocking
import java.io.File

/**
 * [KernelRuntime] 的生产实现：把旧 `KernelHost` 里的 bootstrap / command server / buildConfig /
 * newService / start / close / teardown 代码**原样搬迁**到这里，内部逻辑不变。
 *
 * 与旧实现相比只有这几处边界调整（都是为了让协调器能保证「完整回收、不遗漏」）：
 *   1. 输入来自 [LaunchSpec]，不再读 Prefs 的 activeConfigPath/options；
 *   2. 每个阻塞调用一返回就检查 [ExecContext.cancelled]，被取消就不再进入下一个原生步骤
 *      （顺序与检查点见 [runStartSequence]）；
 *   3. 创建出来的 CommandServer / libbox BoxService 一出现就记在字段上（旧代码要等 start() 成功
 *      才赋值，start 中途失败或被取消会遗弃局部实例）；
 *   4. 不再自己管状态、通知、stopSelf——这些归协调器与 [KernelHost]；
 *   5. 启动失败不再在这里清理：统一由协调器随后发出的 [teardown] 完成（旧的 abortWithAlert 路径）。
 *
 * 线程：[start] / [teardown] 只在 [KernelExecutor] 的工作线程上执行；
 * [onIdleModeChanged] 沿用旧实现，在主线程由广播接收器调用，所以相关字段是 volatile。
 */
class LibboxKernelRuntime(
    private val service: Service,
    private val platform: PlatformInterface,
    private val logs: LogBuffer,
    private val onReloadRequested: () -> Unit,
) : KernelRuntime, CommandServerHandler {

    companion object {
        private const val TAG = "engine/KernelRuntime"
        private const val RELOAD_SETTLE_MS = 1000L

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

        /** sing-box config 文本解析（Pigeon validateConfig 直接调）。 */
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
    }

    /** TunnelService.openTun 建好的 FD，被 sing-box 包到 TUN reader 里。 */
    @Volatile var tunFd: ParcelFileDescriptor? = null

    @Volatile private var libboxService: LibboxBoxService? = null
    @Volatile private var commandServer: CommandServer? = null

    // === KernelRuntime ======================================================

    override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult =
        runStartSequence(startOps, spec, reload, ctx)

    /** 启动链的原生步骤；顺序与取消检查点由 [runStartSequence] 统一掌握。 */
    private val startOps = object : KernelStartOps {
        override fun bootstrap() = bootstrapOnce()

        override fun hasCommandServer(): Boolean = commandServer != null

        override fun spawnCommandServer() = this@LibboxKernelRuntime.spawnCommandServer()

        override fun buildConfig(spec: LaunchSpec): String {
            val content = try {
                Mobile.buildConfig(spec.runtimeConfigPath, spec.optionsJson)
            } catch (e: Exception) {
                Log.w(TAG, "buildConfig failed", e)
                throw e
            }
            if (Prefs.Engine.debugMode) {
                File(workingDir, "current-config.json").writeText(content)
            }
            return content
        }

        override fun prepareRuntime() {
            // logs 在 reload / start 的时候清一次，让 UI 从干净状态开始。
            logs.reset(emptyList())
            runBlocking { NetworkWatcher.arm() }
            Libbox.registerLocalDNSTransport(SystemDnsBridge)
            Libbox.setMemoryLimit(!Prefs.Engine.disableMemoryLimit)
        }

        override fun newService(content: String) {
            // 所有权立刻归 runtime：之后无论取消还是失败，teardown 都能关掉它。
            libboxService = Libbox.newService(content, platform)
        }

        // 重载：等旧资源释放（旧实现里 serviceReload → launchKernel(retryAfter = 1000)）。
        override fun settleAfterReload(ctx: ExecContext): Boolean =
            this@LibboxKernelRuntime.settleAfterReload(ctx)

        override fun startService() {
            checkNotNull(libboxService) { "libbox service missing" }.start()
        }

        override fun bindCommandServer() {
            commandServer?.setService(libboxService)
        }
    }

    private fun settleAfterReload(ctx: ExecContext): Boolean {
        ctx.step("reloadSettle")
        var waited = 0L
        while (waited < RELOAD_SETTLE_MS) {
            if (ctx.cancelled) return false
            Thread.sleep(100)
            waited += 100
        }
        return !ctx.cancelled
    }

    private fun spawnCommandServer() {
        val server = CommandServer(this, 300)
        commandServer = server // 先记名下，start() 失败也能被回收
        server.start()
    }

    /**
     * 拆除内核运行时资源：关闭 Android 侧原始 tun fd（撤销系统路由表）、断开
     * command server 与 libbox service 的绑定、销毁 libbox service、注销本地
     * DNS transport、disarm 默认网络监听、彻底关闭 command server 自身（native
     * 引用一并 destroy）。
     *
     * [soft] 是重载用的：只做前三件（与旧 serviceReload 一致），保留 command server 与网络监听。
     *
     * 每个原生清理各自 runCatching 兜底：任一步抛异常（尤其闭源 libbox 的
     * registerLocalDNSTransport、或 CommandServer.close）都不得中断后续清理。
     * 历史上 abortWithAlert 先后漏过 tun fd / libbox service、DNS transport 注销 /
     * NetworkWatcher disarm / commandServer 关闭，导致启动失败重试时泄漏 native 资源——
     * 现在所有终结路径都只经这一个函数收口。全部步骤幂等：提前 abort 时没创建的资源
     * 都是 null-safe no-op。
     */
    override fun teardown(soft: Boolean, ctx: ExecContext) {
        ctx.step("closeTun")
        closeTunFd()
        ctx.step("detachService")
        runCatching { commandServer?.setService(null) }
        ctx.step("closeService")
        teardownLibboxService()
        if (soft) return

        ctx.step("closeRuntime")
        runCatching { Libbox.registerLocalDNSTransport(null) }
        runCatching { runBlocking { NetworkWatcher.disarm() } }
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
        runCatching { Seq.destroyRef(running.refnum) }
        libboxService = null
    }

    fun writeLog(message: String) {
        logs.append(message)
    }

    /** 设备空闲（Doze）进出：沿用旧实现，暂停 / 唤醒 libbox。 */
    fun onIdleModeChanged() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (Application.powerManager.isDeviceIdleMode) libboxService?.pause()
        else libboxService?.wake()
    }

    // === CommandServerHandler（libbox → App）===================================

    override fun serviceReload() {
        onReloadRequested()
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        val status = SystemProxyStatus()
        val tun = service as? TunnelService ?: return status
        status.available = tun.systemProxyAvailable
        status.enabled = tun.systemProxyEnabled
        return status
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {
        onReloadRequested()
    }

    override fun postServiceClose() {
        // Android 端不需要：libbox 关闭由协调器驱动。
    }
}
