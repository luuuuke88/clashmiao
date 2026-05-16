package com.clashmiao.clashmiao.engine

import android.app.Service
import android.content.Intent

/**
 * Proxy-only 模式的前台 service —— 不申请 VPN 权限，只跑 mixed-port HTTP/SOCKS。
 *
 * 因为没 TUN，[LibboxHost.openTun] 用基类的默认实现（throw），sing-box 这种模式
 * 下不会触发 openTun。其他逻辑（lifecycle / log / status）都走 [KernelHost]，
 * 跟 [TunnelService] 共用同一份内核。
 */
class PlainService : Service() {

    private val libboxHost: LibboxHost = object : LibboxHost() {
        override fun writeLog(message: String) {
            host.writeLog(message)
        }
    }
    private val host: KernelHost = KernelHost(this, libboxHost)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        host.onStartCommand(intent, flags, startId)

    override fun onBind(intent: Intent) = host.onBind(intent)

    override fun onDestroy() = host.onDestroy()

    fun writeLog(message: String) = host.writeLog(message)
}
