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
import com.clashmiao.clashmiao.engine.KernelCoordinator
import com.clashmiao.clashmiao.engine.Source

/**
 * 桌面快捷方式：切换连接。不再绑定 Service 读状态——直接向进程级协调器提交一个
 * source=shortcut 的外部请求（按当前 desired 翻转），然后立即结束。
 */
class ShortcutActivity : Activity() {

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

        KernelCoordinator.instance.toggleExternal(Source.Shortcut)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            getSystemService<ShortcutManager>()?.reportShortcutUsed("toggle")
        }
        finish()
    }
}
