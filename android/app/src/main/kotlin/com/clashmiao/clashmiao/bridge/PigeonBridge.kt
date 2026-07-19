package com.clashmiao.clashmiao.bridge

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.MainActivity
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.engine.KernelHost
import com.clashmiao.clashmiao.pigeon.BoxHostApi
import com.clashmiao.clashmiao.pigeon.ConfigOptions
import com.clashmiao.clashmiao.pigeon.InstalledApp
import com.clashmiao.clashmiao.pigeon.SelectOutboundRequest
import com.clashmiao.clashmiao.pigeon.StartRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Pigeon 强类型 host API 桥 —— 跟 [MethodBridge] 并存的过渡形态。
 *
 * 一个 method 一个 method 往这边搬，搬完一个就把 [MethodBridge] 对应 entry 删掉。
 * 已迁：validateConfig、setup、changeConfigOptions、start、stop、restart、
 * selectOutbound、urlTest、generateFullConfig、clearLogs。
 * 全部 kernel method 已迁移，[MethodBridge] kernelOps 表已清空对应条目。
 *
 * Channel namespace 跟 MethodBridge 不冲突：
 *   - MethodBridge: `com.clashmiao.app/method`（字符串契约 MethodChannel）
 *   - PigeonBridge: `dev.flutter.pigeon.clashmiao.BoxHostApi.<method>`（Pigeon 生成）
 */
class PigeonBridge(private val scope: CoroutineScope) : FlutterPlugin, BoxHostApi {
    companion object {
        private const val TAG = "PigeonBridge"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BoxHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BoxHostApi.setUp(binding.binaryMessenger, null)
    }

    // === migrated ==========================================================

    override fun validateConfig(
        req: ValidateConfigRequest,
        callback: (Result<ValidateConfigResult>) -> Unit,
    ) {
        scope.launch(Dispatchers.IO) {
            val errorMessage = KernelHost.parseConfig(req.path, req.tempPath, req.debug)
            val payload = ValidateConfigResult(
                error = errorMessage.takeIf { it.isNotEmpty() },
            )
            callback(Result.success(payload))
        }
    }

    // === migrated (continued) ================================================

    override fun initialize(callback: (Result<Unit>) -> Unit) = pending(callback)

    override fun setup(
        baseDir: String,
        workingDir: String,
        tempDir: String,
        debug: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch(Dispatchers.IO) {
            Mobile.setup()
            callback(Result.success(Unit))
        }
    }

    override fun changeConfigOptions(
        options: ConfigOptions,
        callback: (Result<Unit>) -> Unit,
    ) {
        Prefs.Engine.configOptionsJson = options.jsonOptions
        callback(Result.success(Unit))
    }

    override fun start(req: StartRequest, callback: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.Main) {
            Prefs.Profile.activeConfigPath = req.configPath
            Prefs.Profile.activeName = req.profileName
            val act = MainActivity.instance
            if (act.serviceStatus.value != KernelStatus.Started) {
                act.startService()
            }
            callback(Result.success(Unit))
        }
    }

    override fun stop(callback: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            if (MainActivity.instance.serviceStatus.value == KernelStatus.Started) {
                KernelHost.fireStop()
            }
            callback(Result.success(Unit))
        }
    }

    override fun restart(req: StartRequest, callback: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            Prefs.Profile.activeConfigPath = req.configPath
            Prefs.Profile.activeName = req.profileName
            val act = MainActivity.instance
            val isStarted = withContext(Dispatchers.Main) {
                act.serviceStatus.value == KernelStatus.Started
            }
            if (!isStarted) {
                callback(Result.success(Unit))
                return@launch
            }
            if (Prefs.Engine.shouldRebuildService()) {
                withContext(Dispatchers.Main) { act.reconnect() }
                KernelHost.fireStop()
                delay(1000L)
                withContext(Dispatchers.Main) { act.startService() }
            } else {
                Libbox.newStandaloneCommandClient().serviceReload()
            }
            callback(Result.success(Unit))
        }
    }

    override fun selectOutbound(
        req: SelectOutboundRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        scope.launch(Dispatchers.IO) {
            val groupTag = req.groupTag.trim()
            val outboundTag = req.outboundTag.trim()

            if (groupTag.isBlank() || outboundTag.isBlank()) {
                safeCallback(
                    callback,
                    Result.failure(
                        IllegalArgumentException(
                            "selectOutbound requires non-blank groupTag and outboundTag",
                        ),
                    ),
                )
                return@launch
            }

            kotlin.runCatching {
                Libbox.newStandaloneCommandClient().selectOutbound(groupTag, outboundTag)
            }.fold(
                onSuccess = {
                    safeCallback(callback, Result.success(Unit))
                },
                onFailure = { error ->
                    Log.w(TAG, "selectOutbound($groupTag, $outboundTag) failed", error)
                    safeCallback(
                        callback,
                        Result.failure(Exception(error.message ?: "selectOutbound failed")),
                    )
                },
            )
        }
    }

    override fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            val normalizedGroupTag = groupTag.trim()
            if (normalizedGroupTag.isBlank()) {
                safeCallback(
                    callback,
                    Result.failure(
                        IllegalArgumentException("urlTest requires non-blank groupTag"),
                    ),
                )
                return@launch
            }

            kotlin.runCatching {
                Libbox.newStandaloneCommandClient().urlTest(normalizedGroupTag)
            }.fold(
                onSuccess = {
                    safeCallback(callback, Result.success(Unit))
                },
                onFailure = { error ->
                    Log.w(TAG, "urlTest($normalizedGroupTag) failed", error)
                    // 使用标准 Exception 包装，避免异常对象直接穿透导致 Dart Native Host 崩溃。
                    safeCallback(
                        callback,
                        Result.failure(Exception(error.message ?: "urlTest failed")),
                    )
                },
            )
        }
    }

    override fun generateFullConfig(
        path: String,
        callback: (Result<String?>) -> Unit,
    ) {
        scope.launch(Dispatchers.IO) {
            val options = Prefs.Engine.configOptionsJson
            val result = if (options.isBlank() || path.isBlank()) null
                         else KernelHost.buildConfig(path, options)
            callback(Result.success(result))
        }
    }

    override fun clearLogs(callback: (Result<Unit>) -> Unit) {
        MainActivity.instance.logBuffer.clear()
        callback(Result.success(Unit))
    }

    override fun getInstalledApps(callback: (Result<List<InstalledApp>>) -> Unit) {
        scope.launch(Dispatchers.IO) {
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
            callback(Result.success(apps))
        }
    }

    override fun getAppIconBase64(packageName: String, callback: (Result<String?>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            try {
                val pm = MainActivity.instance.packageManager
                val drawable = pm.getApplicationIcon(packageName)
                val bitmap = android.graphics.Bitmap.createBitmap(48, 48, android.graphics.Bitmap.Config.ARGB_8888)
                val canvas = android.graphics.Canvas(bitmap)
                drawable.setBounds(0, 0, 48, 48)
                drawable.draw(canvas)
                val stream = java.io.ByteArrayOutputStream()
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                val b64 = android.util.Base64.encodeToString(stream.toByteArray(), android.util.Base64.NO_WRAP)
                callback(Result.success(b64))
            } catch (e: Exception) {
                callback(Result.success(null))
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
