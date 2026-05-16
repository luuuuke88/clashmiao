package com.clashmiao.clashmiao.bridge

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.util.Base64
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.MainActivity
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.engine.KernelHost
import com.clashmiao.clashmiao.core.KernelStatus
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.StandardMethodCodec
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.mobile.Mobile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream

/**
 * Dart → native 单向 RPC 总线。
 *
 * 持有两条 MethodChannel：
 *   - 内核生命周期 / 配置 ([CHANNEL_KERNEL])
 *   - 跨平台系统能力（电量豁免、装机应用列表、应用图标）([CHANNEL_PLATFORM])
 *
 * 之前是 7 个 `*Handler` / `*Channel` 类各自实现 [FlutterPlugin]，
 * 这里整合到一个类、用方法名 → suspend handler 的 map dispatch。新加 method
 * 加一行 [register]，参数解析在 handler 内部，错误统一 try/catch 走
 * [MethodChannel.Result.error]。
 */
class MethodBridge(
    private val scope: CoroutineScope,
) : FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val CHANNEL_KERNEL = "com.clashmiao.app/method"
        private const val CHANNEL_PLATFORM = "com.clashmiao.app/platform"
        private const val REQ_BATTERY_OPTIMIZATION = 44
        private val gson = Gson()
    }

    private var kernelChannel: MethodChannel? = null
    private var platformChannel: MethodChannel? = null
    private var activity: Activity? = null
    private var pendingBatteryResult: MethodChannel.Result? = null

    // 内核 channel handler 表：method name → 该方法的处理函数。
    // 注意：parse_config 已迁去 PigeonBridge.validateConfig；后续每搬一条这里就删一条。
    private val kernelOps: Map<String, KernelOp> = buildMap {
        put("setup", ::opSetup)
        put("change_config_options", ::opChangeConfigOptions)
        put("generate_config", ::opGenerateConfig)
        put("start", ::opStart)
        put("stop", ::opStop)
        put("restart", ::opRestart)
        put("select_outbound", ::opSelectOutbound)
        put("url_test", ::opUrlTest)
        put("clear_logs", ::opClearLogs)
        put("generate_warp_config", ::opGenerateWarpConfig)
    }

    private val platformOps: Map<String, PlatformOp> = buildMap {
        put("is_ignoring_battery_optimizations", ::opIsIgnoringBattery)
        put("request_ignore_battery_optimizations", ::opRequestIgnoreBattery)
        put("get_installed_packages", ::opGetInstalledPackages)
        put("get_package_icon", ::opGetPackageIcon)
    }

    // === FlutterPlugin =====================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kernelChannel = MethodChannel(binding.binaryMessenger, CHANNEL_KERNEL).also {
            it.setMethodCallHandler { call, result -> routeKernel(call, result) }
        }
        platformChannel = MethodChannel(
            binding.binaryMessenger,
            CHANNEL_PLATFORM,
            StandardMethodCodec.INSTANCE,
            binding.binaryMessenger.makeBackgroundTaskQueue(),
        ).also {
            it.setMethodCallHandler { call, result -> routePlatform(call, result) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        kernelChannel?.setMethodCallHandler(null)
        platformChannel?.setMethodCallHandler(null)
        kernelChannel = null
        platformChannel = null
    }

    // === ActivityAware =====================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_BATTERY_OPTIMIZATION) return false
        pendingBatteryResult?.success(resultCode == Activity.RESULT_OK)
        pendingBatteryResult = null
        return true
    }

    // === dispatch ==========================================================

    private fun routeKernel(call: MethodCall, result: MethodChannel.Result) {
        val op = kernelOps[call.method]
        if (op == null) {
            result.notImplemented()
            return
        }
        scope.launch(Dispatchers.IO) {
            try {
                op.invoke(call, result)
            } catch (e: Throwable) {
                result.error("E_KERNEL", e.message, null)
            }
        }
    }

    private fun routePlatform(call: MethodCall, result: MethodChannel.Result) {
        val op = platformOps[call.method]
        if (op == null) {
            result.notImplemented()
            return
        }
        try {
            op.invoke(call, result)
        } catch (e: Throwable) {
            result.error("E_PLATFORM", e.message, null)
        }
    }

    // === kernel ops ========================================================

    private fun argsAsMap(call: MethodCall): Map<*, *> =
        call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()

    private suspend fun opSetup(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        Mobile.setup()
        result.success("")
    }

    private suspend fun opChangeConfigOptions(call: MethodCall, result: MethodChannel.Result) {
        Prefs.Engine.configOptionsJson = call.arguments as String
        result.success(true)
    }

    private suspend fun opGenerateConfig(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        val path = a["path"] as String
        val options = Prefs.Engine.configOptionsJson
        if (options.isBlank() || path.isBlank()) {
            result.error("E_BLANK", "missing path or options", null)
            return
        }
        result.success(KernelHost.buildConfig(path, options))
    }

    private suspend fun opStart(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        Prefs.Profile.activeConfigPath = a["path"] as String? ?: ""
        Prefs.Profile.activeName = a["name"] as String? ?: ""
        val act = MainActivity.instance
        if (act.serviceStatus.value == KernelStatus.Started) {
            result.success(true)
            return
        }
        act.startService()
        result.success(true)
    }

    private suspend fun opStop(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        if (MainActivity.instance.serviceStatus.value != KernelStatus.Started) {
            result.success(true)
            return
        }
        KernelHost.fireStop()
        result.success(true)
    }

    private suspend fun opRestart(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        Prefs.Profile.activeConfigPath = a["path"] as String? ?: ""
        Prefs.Profile.activeName = a["name"] as String? ?: ""
        val act = MainActivity.instance
        if (act.serviceStatus.value != KernelStatus.Started) {
            result.success(true)
            return
        }
        val needRestart = Prefs.Engine.shouldRebuildService()
        if (needRestart) {
            act.reconnect()
            KernelHost.fireStop()
            delay(1000L)
            act.startService()
            result.success(true)
            return
        }
        Libbox.newStandaloneCommandClient().serviceReload()
        result.success(true)
    }

    private suspend fun opSelectOutbound(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        Libbox.newStandaloneCommandClient()
            .selectOutbound(a["groupTag"] as String, a["outboundTag"] as String)
        result.success(true)
    }

    private suspend fun opUrlTest(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        Libbox.newStandaloneCommandClient().urlTest(a["groupTag"] as String)
        result.success(true)
    }

    private suspend fun opClearLogs(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        MainActivity.instance.logBuffer.clear()
        result.success(true)
    }

    private suspend fun opGenerateWarpConfig(call: MethodCall, result: MethodChannel.Result) {
        val a = argsAsMap(call)
        result.success(
            Mobile.generateWarpConfig(
                a["license-key"] as String,
                a["previous-account-id"] as String,
                a["previous-access-token"] as String,
            ),
        )
    }

    // === platform ops ======================================================

    @SuppressLint("BatteryLife")
    private fun opIsIgnoringBattery(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Application.powerManager
                .isIgnoringBatteryOptimizations(Application.application.packageName)
        } else {
            true
        }
        result.success(ok)
    }

    private fun opRequestIgnoreBattery(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        val intent = Intent(
            android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${Application.application.packageName}"),
        )
        pendingBatteryResult = result
        activity?.startActivityForResult(intent, REQ_BATTERY_OPTIMIZATION)
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun opGetInstalledPackages(@Suppress("UNUSED_PARAMETER") call: MethodCall, result: MethodChannel.Result) {
        // 故意用 GlobalScope —— Activity scope 可能在用户离开时被取消，但 PackageManager
        // 列表扫描应该自然跑完，不能因为 UI 跳走就让 Dart 端 result 永远没回复。
        GlobalScope.launch(Dispatchers.IO) {
            val pm = Application.packageManager
            val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                PackageManager.GET_PERMISSIONS or PackageManager.MATCH_UNINSTALLED_PACKAGES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_PERMISSIONS or PackageManager.GET_UNINSTALLED_PACKAGES
            }
            val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(flag.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(flag)
            }
            val self = Application.application.packageName
            val rows = ArrayList<AppRow>(packages.size)
            for (p in packages) {
                if (p.packageName == self) continue
                val isAndroidStub = p.packageName == "android"
                val hasInternet =
                    p.requestedPermissions?.contains(Manifest.permission.INTERNET) == true
                if (!hasInternet && !isAndroidStub) continue
                val label = p.applicationInfo?.loadLabel(pm)?.toString() ?: p.packageName
                val isSystem = (p.applicationInfo?.flags ?: 0) and ApplicationInfo.FLAG_SYSTEM == 1
                rows.add(AppRow(p.packageName, label, isSystem))
            }
            rows.sortBy { it.name }
            result.success(gson.toJson(rows))
        }
    }

    private fun opGetPackageIcon(call: MethodCall, result: MethodChannel.Result) {
        val pkg = (call.arguments as Map<*, *>)["packageName"] as String
        val drawable = Application.packageManager.getApplicationIcon(pkg)
        val bmp = Bitmap.createBitmap(
            drawable.intrinsicWidth,
            drawable.intrinsicHeight,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        val sink = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, sink)
        result.success(Base64.encodeToString(sink.toByteArray(), Base64.NO_WRAP))
    }
}

/** Dart 端按 'package-name'/'name'/'is-system-app' kebab-case 解析（gson @SerializedName）。 */
private data class AppRow(
    @SerializedName("package-name") val packageName: String,
    @SerializedName("name") val name: String,
    @SerializedName("is-system-app") val isSystemApp: Boolean,
)

private typealias KernelOp = suspend (MethodCall, MethodChannel.Result) -> Unit
private typealias PlatformOp = (MethodCall, MethodChannel.Result) -> Unit
