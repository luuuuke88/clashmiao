package com.clashmiao.clashmiao

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.getSystemService
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.clashmiao.clashmiao.core.KernelStatus
import com.clashmiao.clashmiao.engine.KernelConnection
import com.clashmiao.clashmiao.engine.KernelHost

class ShortcutActivity : Activity(), KernelConnection.Sink {

    private val connection = KernelConnection(this, this, registerCallback = false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == Intent.ACTION_CREATE_SHORTCUT) {
            setResult(
                RESULT_OK,
                ShortcutManagerCompat.createShortcutResultIntent(
                    this,
                    ShortcutInfoCompat.Builder(this, "toggle")
                        .setIntent(
                            Intent(this, ShortcutActivity::class.java)
                                .setAction(Intent.ACTION_MAIN),
                        )
                        .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher))
                        .setShortLabel(getString(R.string.quick_toggle))
                        .build(),
                ),
            )
            finish()
            return
        }

        connection.connect()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            getSystemService<ShortcutManager>()?.reportShortcutUsed("toggle")
        }
        moveTaskToBack(true)
    }

    override fun onStatusChange(status: KernelStatus) {
        when (status) {
            KernelStatus.Started -> KernelHost.fireStop()
            KernelStatus.Stopped -> KernelHost.fireStart()
            else -> Unit
        }
        finish()
    }

    override fun onDestroy() {
        connection.disconnect()
        super.onDestroy()
    }
}
