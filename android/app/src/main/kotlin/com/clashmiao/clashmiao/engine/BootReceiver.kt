package com.clashmiao.clashmiao.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机 / 升级后按**持久化的 desired**恢复连接（取代旧的 `startedByUser`）：
 * 上次是 on 就以 source=boot 向协调器提交外部请求，配置取持久化的最近 LaunchSpec。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> Unit
            else -> return
        }

        KernelCoordinator.instance.resumeFromBoot()
    }
}
