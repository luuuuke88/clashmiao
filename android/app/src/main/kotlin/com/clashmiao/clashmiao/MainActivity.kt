package com.clashmiao.clashmiao

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*

class MainActivity : FlutterActivity() {

    private val CHANNEL_PREFIX = "com.clashmiao.app"
    private val VPN_REQUEST_CODE = 1001

    private var statusSink: EventChannel.EventSink? = null
    private var statsSink: EventChannel.EventSink? = null
    private var groupsSink: EventChannel.EventSink? = null
    private var logsSink: EventChannel.EventSink? = null

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Method Channel
        MethodChannel(messenger, "$CHANNEL_PREFIX/method").setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }

        // Status Event Channel
        EventChannel(messenger, "$CHANNEL_PREFIX/service.status", JSONMethodCodec.INSTANCE)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statusSink = events
                    events?.success(mapOf("status" to "stopped"))
                }
                override fun onCancel(arguments: Any?) { statusSink = null }
            })

        // Stats Event Channel
        EventChannel(messenger, "$CHANNEL_PREFIX/stats", JSONMethodCodec.INSTANCE)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    statsSink = events
                }
                override fun onCancel(arguments: Any?) { statsSink = null }
            })

        // Groups Event Channel
        EventChannel(messenger, "$CHANNEL_PREFIX/groups")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    groupsSink = events
                }
                override fun onCancel(arguments: Any?) { groupsSink = null }
            })

        // Logs Event Channel
        EventChannel(messenger, "$CHANNEL_PREFIX/service.logs")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    logsSink = events
                }
                override fun onCancel(arguments: Any?) { logsSink = null }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setup" -> {
                // TODO: 初始化 sing-box 核心
                result.success(true)
            }

            "start" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARGS", "缺少 path 参数", null)
                    return
                }
                // 请求 VPN 权限
                val intent = VpnService.prepare(this)
                if (intent != null) {
                    pendingResult = result
                    startActivityForResult(intent, VPN_REQUEST_CODE)
                } else {
                    // 已有权限，直接启动
                    startVpn(path, result)
                }
            }

            "stop" -> {
                // TODO: 停止 VPN 服务
                statusSink?.success(mapOf("status" to "stopped"))
                result.success(true)
            }

            "restart" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARGS", "缺少 path 参数", null)
                    return
                }
                // TODO: 重启 VPN 服务
                result.success(true)
            }

            "parse_config" -> {
                val path = call.argument<String>("path")
                val tempPath = call.argument<String>("tempPath")
                // TODO: 验证配置文件
                result.success("")
            }

            "select_outbound" -> {
                val groupTag = call.argument<String>("groupTag")
                val outboundTag = call.argument<String>("outboundTag")
                // TODO: 切换出站代理
                result.success(true)
            }

            "url_test" -> {
                val groupTag = call.argument<String>("groupTag")
                // TODO: 延迟测试
                result.success(true)
            }

            "generate_config" -> {
                val path = call.argument<String>("path")
                // TODO: 生成完整配置
                result.success("")
            }

            "change_config_options" -> {
                // TODO: 更新配置选项
                result.success(true)
            }

            "clear_logs" -> {
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun startVpn(configPath: String, result: MethodChannel.Result) {
        // TODO: 启动 VpnService，传入配置路径
        statusSink?.success(mapOf("status" to "starting"))
        // 模拟启动
        statusSink?.success(mapOf("status" to "started"))
        result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                // 用户授权了 VPN 权限
                // TODO: 启动 VPN
                pendingResult?.success(true)
            } else {
                pendingResult?.error("VPN_DENIED", "用户拒绝了 VPN 权限", null)
            }
            pendingResult = null
        }
    }
}
