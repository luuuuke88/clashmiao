package com.clashmiao.clashmiao.bridge

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.engine.Desired
import com.clashmiao.clashmiao.engine.KernelCoordinator
import com.clashmiao.clashmiao.engine.KernelSnapshot
import com.clashmiao.clashmiao.engine.LaunchSpec
import com.clashmiao.clashmiao.engine.LibboxKernelRuntime
import com.clashmiao.clashmiao.pigeon.BoxHostApi
import com.clashmiao.clashmiao.pigeon.ConfigOptions
import com.clashmiao.clashmiao.pigeon.DesiredRequestMsg
import com.clashmiao.clashmiao.pigeon.FlutterError
import com.clashmiao.clashmiao.pigeon.InstalledApp
import com.clashmiao.clashmiao.pigeon.KernelFailureMsg
import com.clashmiao.clashmiao.pigeon.KernelSnapshotMsg
import com.clashmiao.clashmiao.pigeon.ReceiptMsg
import com.clashmiao.clashmiao.pigeon.SelectOutboundRequest
import com.clashmiao.clashmiao.pigeon.StartRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

/**
 * Pigeon 强类型 host API 桥。
 *
 * 连接生命周期走进程级 [KernelCoordinator]：`getSnapshot` / `request` / `acknowledgeReplay`
 * 是新协议；旧的 `start` / `stop` / `restart` 只是转发到协调器（供尚未迁移的旧调用方）。
 *
 * **错误契约**：每个回调都恰好被调用一次，失败一律 `Result.failure(FlutterError(...))`，
 * 绝不在协程里抛出（旧实现里 setup / generateFullConfig / restart 的异常会直接崩进程，
 * 或让 Dart 的 Future 永远悬挂）。
 *
 * Channel namespace 跟 MethodBridge 不冲突：
 *   - MethodBridge: `com.clashmiao.app/method`（字符串契约 MethodChannel）
 *   - PigeonBridge: `dev.flutter.pigeon.clashmiao.BoxHostApi.<method>`（Pigeon 生成）
 */
class PigeonBridge(private val scope: CoroutineScope) : FlutterPlugin, BoxHostApi {
    companion object {
        private const val TAG = "PigeonBridge"

        /** 旧 start/restart 没有 revision：用进程内递增值保证每次都被视为「新配置」。 */
        private val legacyRevision = AtomicLong(1L shl 40)
    }

    private val coordinator get() = KernelCoordinator.instance

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BoxHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BoxHostApi.setUp(binding.binaryMessenger, null)
    }

    // === 错误契约 ===========================================================

    /** 同步执行 [block]（主线程），任何异常都转成 FlutterError 回调。 */
    private fun <T> respond(callback: (Result<T>) -> Unit, code: String, block: () -> T) {
        val result = try {
            Result.success(block())
        } catch (e: FlutterError) {
            Result.failure(e)
        } catch (e: Exception) {
            Log.w(TAG, "$code failed", e)
            Result.failure(FlutterError(code, e.message ?: e.toString(), null))
        }
        safeCallback(callback, result)
    }

    /** 在协程里执行 [block]；异常转 FlutterError，取消异常照常向上抛（协程框架需要它）。 */
    private fun <T> launchResponding(
        dispatcher: kotlinx.coroutines.CoroutineDispatcher,
        callback: (Result<T>) -> Unit,
        code: String,
        block: suspend () -> T,
    ) {
        scope.launch(dispatcher) {
            val result = try {
                Result.success(block())
            } catch (e: CancellationException) {
                throw e
            } catch (e: FlutterError) {
                Result.failure(e)
            } catch (e: Exception) {
                Log.w(TAG, "$code failed", e)
                Result.failure(FlutterError(code, e.message ?: e.toString(), null))
            }
            safeCallback(callback, result)
        }
    }

    // === 配置 / 校验 ==========================================================

    override fun validateConfig(
        req: ValidateConfigRequest,
        callback: (Result<ValidateConfigResult>) -> Unit,
    ) {
        launchResponding(Dispatchers.IO, callback, "validateConfig") {
            val errorMessage = LibboxKernelRuntime.parseConfig(req.path, req.tempPath, req.debug)
            ValidateConfigResult(error = errorMessage.takeIf { it.isNotEmpty() })
        }
    }

    override fun initialize(callback: (Result<Unit>) -> Unit) = pending(callback)

    override fun setup(
        baseDir: String,
        workingDir: String,
        tempDir: String,
        debug: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        launchResponding(Dispatchers.IO, callback, "setup") { Mobile.setup() }
    }

    override fun changeConfigOptions(
        options: ConfigOptions,
        callback: (Result<Unit>) -> Unit,
    ) {
        respond(callback, "changeConfigOptions") {
            Prefs.Engine.configOptionsJson = options.jsonOptions
        }
    }

    // === 旧生命周期入口：转发协调器（计划 P2④）===================================
    //
    // 旧 Dart 控制器仍按「changeConfigOptions → start(path)」的节奏调用；这里把它们翻译成
    // 不带序号的协调器请求（不推进 appliedSeq）。结果不再「立即成功」后靠推送补——
    // 启动成败由协调器快照 / 状态流如实反映。

    override fun start(req: StartRequest, callback: (Result<Unit>) -> Unit) {
        respond(callback, "start") {
            coordinator.legacyStart(legacySpec(req))
        }
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        respond(callback, "stop") { coordinator.legacyStop() }
    }

    override fun restart(req: StartRequest, callback: (Result<Unit>) -> Unit) {
        respond(callback, "restart") {
            coordinator.legacyRestart(legacySpec(req))
        }
    }

    private fun legacySpec(req: StartRequest): LaunchSpec {
        // 旧调用方的配置选项由 changeConfigOptions 预先写进 Prefs。
        Prefs.Profile.activeConfigPath = req.configPath
        Prefs.Profile.activeName = req.profileName
        return LaunchSpec(
            runtimeConfigPath = req.configPath,
            optionsJson = Prefs.Engine.configOptionsJson,
            profileName = req.profileName,
            configRevision = legacyRevision.incrementAndGet(),
        )
    }

    // === 出站选择 ============================================================

    override fun selectOutbound(
        req: SelectOutboundRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        // attempt 校验放在主线程、与快照同一视角：重放属于哪次内核实例，由原生说了算（spec §10.7）。
        val expected = req.expectedAttempt
        if (expected != null && coordinator.snapshot.attempt != expected) {
            safeCallback(
                callback,
                Result.failure(
                    FlutterError(
                        "stale",
                        "attempt ${coordinator.snapshot.attempt} != expected $expected",
                        null,
                    ),
                ),
            )
            return
        }
        launchResponding(Dispatchers.IO, callback, "selectOutbound") {
            val groupTag = req.groupTag.trim()
            val outboundTag = req.outboundTag.trim()
            if (groupTag.isBlank() || outboundTag.isBlank()) {
                throw IllegalArgumentException(
                    "selectOutbound requires non-blank groupTag and outboundTag",
                )
            }
            Libbox.newStandaloneCommandClient().selectOutbound(groupTag, outboundTag)
        }
    }

    // === 连接生命周期协议（spec §2 / §10）====================================

    override fun getSnapshot(callback: (Result<KernelSnapshotMsg>) -> Unit) {
        respond(callback, "getSnapshot") { coordinator.snapshot.toMsg() }
    }

    override fun request(
        req: DesiredRequestMsg,
        callback: (Result<ReceiptMsg>) -> Unit,
    ) {
        respond(callback, "request") {
            val desired = when (req.desired) {
                Desired.On.wire -> Desired.On
                Desired.Off.wire -> Desired.Off
                else -> throw FlutterError("invalid", "unknown desired '${req.desired}'", null)
            }
            val launch = req.launch?.let {
                LaunchSpec(it.runtimeConfigPath, it.optionsJson, it.profileName, it.configRevision)
            }
            if (desired == Desired.On && launch == null) {
                throw FlutterError("invalid", "desired=on requires launch", null)
            }
            val receipt = coordinator.request(req.epoch, req.seq, desired, launch, req.reason)
            ReceiptMsg(
                accepted = receipt.accepted,
                reason = receipt.reason?.wire,
                epoch = receipt.epoch,
                appliedSeq = receipt.appliedSeq,
            )
        }
    }

    override fun acknowledgeReplay(attempt: Long, callback: (Result<Unit>) -> Unit) {
        respond(callback, "acknowledgeReplay") { coordinator.acknowledgeReplay(attempt) }
    }

    private fun KernelSnapshot.toMsg() = KernelSnapshotMsg(
        epoch = epoch,
        version = version,
        status = status.name.lowercase(),
        attempt = attempt,
        desired = desired.wire,
        source = source.wire,
        appliedSeq = appliedSeq,
        activeConfigRevision = activeConfigRevision,
        lastFailure = lastFailure?.let {
            KernelFailureMsg(
                code = it.code.wire,
                message = it.message,
                attempt = it.attempt,
                seq = it.seq,
            )
        },
        selectionsReplayNeeded = selectionsReplayNeeded,
    )

    override fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) {
        launchResponding(Dispatchers.IO, callback, "urlTest") {
            val normalizedGroupTag = groupTag.trim()
            if (normalizedGroupTag.isBlank()) {
                throw IllegalArgumentException("urlTest requires non-blank groupTag")
            }
            Libbox.newStandaloneCommandClient().urlTest(normalizedGroupTag)
        }
    }

    override fun generateFullConfig(
        path: String,
        callback: (Result<String?>) -> Unit,
    ) {
        launchResponding(Dispatchers.IO, callback, "generateFullConfig") {
            val options = Prefs.Engine.configOptionsJson
            if (options.isBlank() || path.isBlank()) null
            else LibboxKernelRuntime.buildConfig(path, options)
        }
    }

    override fun clearLogs(callback: (Result<Unit>) -> Unit) {
        respond(callback, "clearLogs") { coordinator.logs.clear() }
    }

    override fun getInstalledApps(callback: (Result<List<InstalledApp>>) -> Unit) {
        launchResponding(Dispatchers.IO, callback, "getInstalledApps") {
            val pm = Application.packageManager
            val self = Application.application.packageName
            val byPackage = LinkedHashMap<String, ApplicationInfo>()
            fun addApp(appInfo: ApplicationInfo?) {
                if (appInfo == null) return
                val packageName = appInfo.packageName
                if (packageName == self || packageName.isBlank()) return
                byPackage[packageName] = appInfo
            }

            val applications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledApplications(0)
            }
            applications.forEach(::addApp)

            val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val launcherActivities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(
                    launcherIntent,
                    PackageManager.ResolveInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(launcherIntent, 0)
            }
            launcherActivities.forEach { addApp(it.activityInfo?.applicationInfo) }

            val apps = byPackage.values.map { appInfo ->
                InstalledApp(
                    packageName = appInfo.packageName,
                    appName = appInfo.loadLabel(pm)?.toString() ?: appInfo.packageName,
                    isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0,
                )
            }.sortedWith(
                compareBy<InstalledApp> { it.isSystemApp }
                    .thenBy { it.appName.lowercase() },
            )
            apps
        }
    }

    override fun getAppIconBase64(packageName: String, callback: (Result<String?>) -> Unit) {
        launchResponding(Dispatchers.IO, callback, "getAppIconBase64") {
            try {
                val pm = Application.packageManager
                val drawable = pm.getApplicationIcon(packageName)
                val bitmap = android.graphics.Bitmap.createBitmap(48, 48, android.graphics.Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bitmap)
                drawable.setBounds(0, 0, 48, 48)
                drawable.draw(canvas)
                val stream = java.io.ByteArrayOutputStream()
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
            } catch (e: Exception) {
                null
            }
        }
    }

    override fun resetTunnel(callback: (Result<Unit>) -> Unit) {
        callback(Result.success(Unit))
    }

    /// iOS 专用能力的 Android 桩实现——见 pigeons/box_api.dart 方法文档。
    /// Android 是单进程模型，没有"另一个进程看不到私有沙盒"的问题，Dart 侧
    /// 目录解析（`resolveSingBoxWorkingDirectory`）在 Android 上继续走
    /// `path_provider`，根本不会调用这个方法；这里给一个合理值只是为了满足
    /// Pigeon 生成的接口契约（不实现就编译不过），不影响 Android 现有行为。
    override fun getAppGroupWorkingDirectory(callback: (Result<String>) -> Unit) {
        callback(Result.success(Application.application.filesDir.absolutePath))
    }

    private fun <T> pending(callback: (Result<T>) -> Unit) {
        callback(Result.failure(NotImplementedError("not migrated to Pigeon yet")))
    }

    private fun <T> safeCallback(
        callback: (Result<T>) -> Unit,
        result: Result<T>,
    ) {
        try {
            callback(result)
        } catch (error: Exception) {
            Log.w(TAG, "callback invocation failed", error)
        }
    }
}
