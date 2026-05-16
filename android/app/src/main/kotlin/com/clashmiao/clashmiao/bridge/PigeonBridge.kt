package com.clashmiao.clashmiao.bridge

import com.clashmiao.clashmiao.engine.KernelHost
import com.clashmiao.clashmiao.pigeon.BoxHostApi
import com.clashmiao.clashmiao.pigeon.ConfigOptions
import com.clashmiao.clashmiao.pigeon.SelectOutboundRequest
import com.clashmiao.clashmiao.pigeon.StartRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigRequest
import com.clashmiao.clashmiao.pigeon.ValidateConfigResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Pigeon 强类型 host API 桥 —— 跟 [MethodBridge] 并存的过渡形态。
 *
 * 一个 method 一个 method 往这边搬，搬完一个就把 [MethodBridge] 对应 entry 删掉。
 * 现在第一条 wired 的是 [validateConfig]（被 PlatformBoxService.validateConfig 调）。
 * 其他 11 个 method 留 stub 返回 Result.failure，未迁完前 Dart 端继续走 MethodBridge。
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

    // === pending migration: 都 fail 着，Dart 端继续走 MethodBridge =============

    override fun init(callback: (Result<Unit>) -> Unit) = pending(callback)
    override fun setup(
        baseDir: String,
        workingDir: String,
        tempDir: String,
        debug: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) = pending(callback)

    override fun changeConfigOptions(
        options: ConfigOptions,
        callback: (Result<Unit>) -> Unit,
    ) = pending(callback)

    override fun start(req: StartRequest, callback: (Result<Unit>) -> Unit) = pending(callback)
    override fun stop(callback: (Result<Unit>) -> Unit) = pending(callback)
    override fun restart(req: StartRequest, callback: (Result<Unit>) -> Unit) = pending(callback)
    override fun selectOutbound(req: SelectOutboundRequest, callback: (Result<Unit>) -> Unit) =
        pending(callback)
    override fun urlTest(groupTag: String, callback: (Result<Unit>) -> Unit) = pending(callback)
    override fun generateFullConfig(path: String, callback: (Result<String?>) -> Unit) =
        pending(callback)
    override fun clearLogs(callback: (Result<Unit>) -> Unit) = pending(callback)

    private fun <T> pending(callback: (Result<T>) -> Unit) {
        callback(Result.failure(NotImplementedError("not migrated to Pigeon yet")))
    }
}
