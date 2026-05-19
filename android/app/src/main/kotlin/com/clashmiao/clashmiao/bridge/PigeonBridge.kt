package com.clashmiao.clashmiao.bridge

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

    override fun init(callback: (Result<Unit>) -> Unit) = pending(callback)

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
        scope.launch(Dispatchers.Main) {
            Prefs.Profile.activeConfigPath = req.configPath
            Prefs.Profile.activeName = req.profileName
            val act = MainActivity.instance
            if (act.serviceStatus.value != KernelStatus.Started) {
                callback(Result.success(Unit))
                return@launch
            }
            if (Prefs.Engine.shouldRebuildService()) {
                act.reconnect()
                KernelHost.fireStop()
                delay(1000L)
                act.startService()
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
            Libbox.newStandaloneCommandClient()
                .selectOutbound(req.groupTag, req.outboundTag)
            callback(Result.success(Unit))
        }
    }

    override fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) {
        scope.launch(Dispatchers.IO) {
            Libbox.newStandaloneCommandClient().urlTest(groupTag)
            callback(Result.success(Unit))
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
            val pm = MainActivity.instance.packageManager
            val apps = pm.getInstalledPackages(0).map { pkg ->
                InstalledApp(
                    packageName = pkg.packageName,
                    appName = pkg.applicationInfo?.loadLabel(pm)?.toString() ?: pkg.packageName,
                    isSystemApp = ((pkg.applicationInfo?.flags ?: 0) and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0,
                )
            }.sortedBy { it.appName }
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

    private fun <T> pending(callback: (Result<T>) -> Unit) {
        callback(Result.failure(NotImplementedError("not migrated to Pigeon yet")))
    }
}
