package com.clashmiao.clashmiao.engine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.clashmiao.clashmiao.core.Prefs

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> Unit
            else -> return
        }

        if (Prefs.Engine.startedByUser) {
            KernelHost.fireStart()
        }
    }
}
