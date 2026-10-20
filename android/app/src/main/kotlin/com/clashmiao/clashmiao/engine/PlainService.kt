package com.clashmiao.clashmiao.engine

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Proxy-only 模式的前台 service —— 不申请 VPN 权限，只跑 mixed-port HTTP/SOCKS。
 *
 * 因为没 TUN，[CorePlatform.openTun] 用基类的默认实现（throw），内核这种模式
 * 下不会触发 openTun。其他逻辑（lifecycle / log / status）都走 [KernelHost]，
 * 跟 [TunnelService] 共用同一份内核。
 */
class PlainService : Service() {

    private val corePlatform: CorePlatform = object : CorePlatform() {
        override fun writeLog(line: String) {
            host.writeLog(line)
        }
    }
    private val host: KernelHost = KernelHost(this, ServiceType.Proxy, corePlatform)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        host.onStartCommand(intent, flags, startId)

    /** 只作为 started service 存在，不提供绑定。 */
    override fun onBind(intent: Intent): IBinder? = null

    override fun onDestroy() {
        host.onDestroy()
        super.onDestroy()
    }

    fun writeLog(message: String) = host.writeLog(message)
}
