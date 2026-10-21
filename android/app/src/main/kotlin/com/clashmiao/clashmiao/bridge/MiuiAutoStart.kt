package com.clashmiao.clashmiao.bridge

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Process
import android.provider.Settings

/**
 * MIUI / HyperOS 的「自启动」权限查询与设置页入口。
 *
 * 背景：这两个系统在 AOSP 之外加了一个私有 AppOp（`MIUIOP(10008)`，即 AUTO_START）。
 * 它被拒绝时，开机广播与「应用更新后」广播在派发阶段就被系统丢弃，进程都不会被拉起，
 * 所以 BootReceiver 里按持久化意图恢复 VPN 的路径根本走不到。普通 Android 没有这个
 * 开关，所以非 MIUI 设备一律回 [UNSUPPORTED]，调用方据此把入口整个藏掉。
 *
 * 判定与「值 → 状态」都做成不依赖 Android 类型的纯函数，方便 JVM 单测直接覆盖。
 */
internal object MiuiAutoStart {

    const val UNSUPPORTED = "unsupported"
    const val ALLOWED = "allowed"
    const val DENIED = "denied"
    const val UNKNOWN = "unknown"

    /** MIUI 私有 AppOp：自启动。 */
    const val OP_AUTO_START = 10008

    // 与 android.app.AppOpsManager 里同名常量取值一致（这些在 SDK 里是 @hide 或随版本变化，
    // 这里自己钉一份，纯函数就不必依赖 android.jar）。
    private const val MODE_ALLOWED = 0
    private const val MODE_IGNORED = 1
    private const val MODE_ERRORED = 2

    private const val AUTOSTART_PKG = "com.miui.securitycenter"
    private const val AUTOSTART_ACTIVITY =
        "com.miui.permcenter.autostart.AutoStartManagementActivity"

    /** 两个厂商系统属性任一非空即视为 MIUI / HyperOS。属性读取失败时调用方传 null。 */
    fun isMiuiOrHyperOs(miuiVersionName: String?, hyperOsVersionName: String?): Boolean =
        !miuiVersionName.isNullOrBlank() || !hyperOsVersionName.isNullOrBlank()

    /**
     * `checkOpNoThrow` 的返回值 → 状态字符串。
     *
     * 只认明确的值：0 放行；1（IGNORED）和 2（ERRORED）是拒绝。MODE_DEFAULT（3）、
     * MODE_FOREGROUND（4）等别的值在这个私有 op 上含义没有公开定义，宁可回 unknown，
     * 也不替系统编一个「已开启 / 未开启」。
     */
    fun statusFromOpMode(mode: Int): String = when (mode) {
        MODE_ALLOWED -> ALLOWED
        MODE_IGNORED, MODE_ERRORED -> DENIED
        else -> UNKNOWN
    }

    private fun systemProperty(key: String): String? = try {
        val cls = Class.forName("android.os.SystemProperties")
        cls.getMethod("get", String::class.java).invoke(null, key) as? String
    } catch (_: Throwable) {
        null
    }

    fun isMiuiOrHyperOs(): Boolean = isMiuiOrHyperOs(
        systemProperty("ro.miui.ui.version.name"),
        systemProperty("ro.mi.os.version.name"),
    )

    /** 完整查询：非 MIUI → unsupported；反射失败 → unknown。 */
    fun status(context: Context): String {
        if (!isMiuiOrHyperOs()) return UNSUPPORTED
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE)
            val method = appOps.javaClass.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
            )
            val mode = method.invoke(appOps, OP_AUTO_START, Process.myUid(), context.packageName) as Int
            statusFromOpMode(mode)
        } catch (_: Throwable) {
            UNKNOWN
        }
    }

    /**
     * 打开自启动管理页；该页不存在 / 不可启动时退回本应用的系统详情页。返回是否成功启动了
     * 其中任何一个。不用 startActivityForResult：系统设置返回后由 Dart 侧在前台恢复时重新查询。
     *
     * 有 Activity 就用它启动（不需要 NEW_TASK）；没有则退回 Application context 并补 NEW_TASK。
     */
    fun openSettings(activity: Activity?, appContext: Context): Boolean {
        val context: Context = activity ?: appContext
        val candidates = listOf(
            Intent().setComponent(ComponentName(AUTOSTART_PKG, AUTOSTART_ACTIVITY)),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${appContext.packageName}"),
            ),
        )
        for (intent in candidates) {
            if (activity == null) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: Exception) {
                // ActivityNotFoundException / SecurityException：试下一个候选
            }
        }
        return false
    }
}
