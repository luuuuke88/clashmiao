package com.clashmiao.clashmiao.engine

import android.app.Service
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.libcore.core.Core
import com.clashmiao.libcore.core.Engine
import com.clashmiao.libcore.core.EngineHandler
import com.clashmiao.libcore.core.Platform
import com.clashmiao.libcore.core.SetupOptions
import go.Seq
import kotlinx.coroutines.runBlocking
import java.io.File

/**
 * 进程内「当前内核实例的 Engine」的唯一出口：流（分组 / 统计）、手选、测速都从这里取。
 *
 * [CoreKernelRuntime] 在 Engine 创建后立刻登记、完整回收时先注销（再关闭），
 * 所以没有人会拿到一个正在被关闭的 Engine。读到 null = 内核尚未就绪，调用方按「未就绪」处理（流会退避重试）。
 */
object EngineRegistry {
    @Volatile var current: Engine? = null
        internal set

    /** 取当前 Engine；没有时抛异常（手选 / 测速：内核没在运行）。 */
    fun require(): Engine = current ?: throw IllegalStateException("kernel engine is not running")
}

/**
 * [KernelRuntime] 的生产实现：自有 Go 门面（[Core] / [Engine]）的 Android 绑定。
 *
 * 资源归属与旧实现一致（让协调器能保证「完整回收、不遗漏」）：
 *   1. 输入来自 [LaunchSpec]，不读 Prefs 的 activeConfigPath/options；
 *   2. 每个阻塞调用一返回就检查 [ExecContext.cancelled]（顺序与检查点见 [runStartSequence]）；
 *   3. 创建出来的 Engine 一出现就记在字段上与 [EngineRegistry] 里，之后无论取消还是失败，teardown 都能关掉它；
 *   4. 不再自己管状态、通知、stopSelf——这些归协调器与 [KernelHost]；
 *   5. 启动失败不在这里清理：统一由协调器随后发出的 [teardown] 完成。
 *
 * 与旧实现相比的行为变化：
 *   - 重载（reload）不再等固定 1 s：直接再次 `engine.start`，内核内部先关旧实例（U18 真机验证重载稳定性）；
 *   - 本地 DNS 经 [CorePlatform.localDNS] 提供，不再注册 / 注销全局传输；内存限制在 setup 时一次性应用。
 *
 * 线程：[start] / [teardown] 只在 [KernelExecutor] 的工作线程上执行；
 * [onIdleModeChanged] 在主线程由广播接收器调用，所以相关字段是 volatile。
 */
class CoreKernelRuntime(
    private val service: Service,
    private val platform: Platform,
    private val logs: LogBuffer,
    private val onReloadRequested: () -> Unit,
) : KernelRuntime, EngineHandler {

    companion object {
        private const val TAG = "engine/KernelRuntime"
        private const val LOG_MAX_LINES = 300

        @Volatile private var initialized = false
        private lateinit var workingDir: File

        /** Core.setup 必须只跑一次；多次 setup 会让旧 service 进程残留。 */
        private fun bootstrapOnce() {
            if (initialized) return
            val app = Application.application
            val baseDir = app.filesDir.also { it.mkdirs() }
            workingDir = (app.getExternalFilesDir(null) ?: return).also { it.mkdirs() }
            val tempDir = app.cacheDir.also { it.mkdirs() }
            Log.d(TAG, "core dirs base=${baseDir.path} working=${workingDir.path}")
            Core.setup(
                SetupOptions().also {
                    it.basePath = baseDir.path
                    it.workingPath = workingDir.path
                    it.tempPath = tempDir.path
                    it.debug = false
                    it.logMaxLines = LOG_MAX_LINES
                    it.memoryLimited = !Prefs.Engine.disableMemoryLimit
                },
            )
            initialized = true
        }

        /**
         * 订阅解析（Pigeon validateConfig 直接调）：[inPath] 是下载的原文，[outPath] 写解析后的 profile。
         * 返回空串表示成功，否则是错误信息（以稳定的错误码前缀开头）。
         */
        fun parseConfig(outPath: String, inPath: String, debug: Boolean): String = try {
            Core.parse(outPath, inPath, debug)
            ""
        } catch (e: Exception) {
            Log.w(TAG, "parseConfig failed", e)
            e.message ?: "invalid config"
        }

        /**
         * 拼最终运行用 config（profile + ConfigOptions JSON），并保证 tun inbound 至多一个
         * （见 [TunInbounds]：旧版本持久化下来的运行配置里留着订阅自带的 tun）。
         */
        fun buildConfig(path: String, options: String): String {
            val r = TunInbounds.keepLast(Core.buildConfig(path, options))
            if (r.removed > 0) Log.w(TAG, "dropped ${r.removed} duplicate tun inbound(s) from $path")
            return r.content
        }
    }

    /** TunnelService.openTun 建好的 FD，被内核包到 TUN reader 里。 */
    @Volatile var tunFd: ParcelFileDescriptor? = null

    @Volatile private var engine: Engine? = null

    /** 回收中各步骤的失败，按发生顺序保留（诊断用；也写进日志缓冲）。 */
    @Volatile var lastTeardownFailures: List<Pair<String, Throwable>> = emptyList()
        private set

    // === KernelRuntime ======================================================

    override fun start(spec: LaunchSpec, reload: Boolean, ctx: ExecContext): JobResult =
        runStartSequence(startOps, spec, reload, ctx)

    private val startOps = object : KernelStartOps {
        override fun bootstrap() = bootstrapOnce()

        override fun createEngine() {
            if (engine != null) return
            // 所有权立刻归 runtime（字段 + 注册表）：之后无论取消还是失败，teardown 都能关掉它。
            val created = Core.newEngine(platform, this@CoreKernelRuntime)
            engine = created
            EngineRegistry.current = created
        }

        override fun buildConfig(spec: LaunchSpec): String {
            val content = try {
                CoreKernelRuntime.buildConfig(spec.runtimeConfigPath, spec.optionsJson)
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
        }

        override fun startEngine(content: String) {
            checkNotNull(engine) { "engine missing" }.start(content)
        }
    }

    private val teardownOps = object : KernelTeardownOps {
        override fun stopEngine() {
            engine?.stop()
        }

        override fun closeTunFd() = this@CoreKernelRuntime.closeTunFd()

        override fun closeEngine() {
            // 先从注册表摘掉：流 / 手选不会再拿到正在关闭的 Engine。
            EngineRegistry.current = null
            engine?.close()
        }

        override fun disarmNetworkWatcher() {
            runBlocking { NetworkWatcher.disarm() }
        }

        override fun releaseEngineRef() {
            val e = engine ?: return
            engine = null
            EngineRegistry.current = null
            Seq.destroyRef(e.refnum)
        }
    }

    /**
     * 拆除内核运行时资源（每一步各自兜底，见 [runTeardown]）。
     *
     * [soft] 是重载用的：只做 stop + 关 tun fd，保留 Engine 与网络监听（统计 / 分组流不断）。
     */
    override fun teardown(soft: Boolean, ctx: ExecContext) {
        val failures = runTeardown(teardownOps, soft, ctx) { step, e ->
            Log.w(TAG, "teardown step $step failed", e)
            writeLog("kernel: $step error: $e")
        }
        lastTeardownFailures = failures
        // Engine 没能关干净时，也不能让注册表继续指向它
        if (!soft) EngineRegistry.current = null
    }

    private fun closeTunFd() {
        val fd = tunFd ?: return
        tunFd = null
        fd.close()
    }

    fun writeLog(message: String) {
        logs.append(message)
    }

    /** 设备空闲（Doze）进出：沿用旧实现，暂停 / 唤醒内核。 */
    fun onIdleModeChanged() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val e = engine ?: return
        if (Application.powerManager.isDeviceIdleMode) e.pause() else e.wake()
    }

    // === EngineHandler（内核 → App）============================================

    override fun onReloadRequested() {
        onReloadRequested.invoke()
    }

    override fun onStopRequested() {
        // Android 端不需要：内核关闭由协调器驱动。
    }

    override fun systemProxyAvailable(): Boolean = (service as? TunnelService)?.systemProxyAvailable ?: false

    override fun systemProxyEnabled(): Boolean = (service as? TunnelService)?.systemProxyEnabled ?: false

    override fun setSystemProxyEnabled(enabled: Boolean) {
        onReloadRequested.invoke()
    }
}
