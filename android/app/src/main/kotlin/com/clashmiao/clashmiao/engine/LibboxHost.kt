package com.clashmiao.clashmiao.engine

import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import androidx.annotation.RequiresApi
import com.clashmiao.clashmiao.Application
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.util.Enumeration
import io.nekohasekai.libbox.NetworkInterface as LibboxIface

/**
 * libbox `PlatformInterface` 的 Android 基类。
 *
 * 之前上游实现是个 `interface PlatformInterfaceWrapper : PlatformInterface`
 * 用 default method 提供默认实现，TunnelService / PlainService 再实现它再加自己的
 * override。这里换成 **abstract class** —— libbox 暴露 ~13 个 method，绝大部分
 * Android 端答案是固定的（受 Android API 约束），用 abstract class 直接把那些
 * "platform" 答案 final 住，子类只需要 override 跟自己 service 类型相关的几个
 * （`openTun` / `autoDetectInterfaceControl`），更难写出脚枪。
 *
 * Note：`openTun` 默认 throw —— [TunnelService] 必须 override 才能起 TUN，
 * [PlainService] 不该被调到这个方法（它没 VPN 模式）。
 */
abstract class LibboxHost : PlatformInterface {

    // ===== 默认实现：不可子类改 ===========================================

    final override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    final override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    final override fun usePlatformDefaultInterfaceMonitor(): Boolean = true

    final override fun usePlatformInterfaceGetter(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    final override fun underNetworkExtension(): Boolean = false

    final override fun includeAllNetworks(): Boolean = false

    final override fun clearDNSCache() {
        // no-op, sing-box 自己的 DNS cache 控制由 enableDnsCache 配置项管
    }

    final override fun readWIFIState(): WIFIState? = null

    @RequiresApi(Build.VERSION_CODES.Q)
    final override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int {
        val uid = Application.connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        return uid
    }

    final override fun packageNameByUid(uid: Int): String {
        val pkgs = Application.packageManager.getPackagesForUid(uid)
        if (pkgs.isNullOrEmpty()) error("android: package not found")
        return pkgs[0]
    }

    @Suppress("DEPRECATION")
    final override fun uidByPackageName(packageName: String): Int = try {
        val pm = Application.packageManager
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
                pm.getPackageUid(packageName, PackageManager.PackageInfoFlags.of(0))
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N ->
                pm.getPackageUid(packageName, 0)
            else ->
                pm.getApplicationInfo(packageName, 0).uid
        }
    } catch (_: PackageManager.NameNotFoundException) {
        error("android: package not found")
    }

    final override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        NetworkWatcher.attachInterfaceListener(listener)
    }

    final override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        NetworkWatcher.attachInterfaceListener(null)
    }

    final override fun getInterfaces(): NetworkInterfaceIterator =
        IfaceCursor(NetworkInterface.getNetworkInterfaces())

    // ===== 子类需要 override 的 =========================================

    override fun autoDetectInterfaceControl(fd: Int) {
        // 默认 no-op；TunnelService 重写为 VpnService.protect(fd)
    }

    override fun openTun(options: TunOptions): Int =
        error("openTun called on a non-VPN service")

    /**
     * sing-box 内部 Log 钩子。每个 Service 把日志 fan-out 给 IPC callback。
     * 抽象方法：每个 Service 必须 wire 到自己持有的 KernelHost.writeLog。
     */
    abstract override fun writeLog(message: String)

    // ===== iterator helpers =============================================
    //
    // 把 java NetworkInterface.Enumeration 包成 libbox NetworkInterfaceIterator。
    // 每个 element 拷字段、IP 地址 / 前缀长度 join 成 "addr/prefix" 字符串数组。

    private class IfaceCursor(
        private val src: Enumeration<NetworkInterface>,
    ) : NetworkInterfaceIterator {

        override fun hasNext(): Boolean = src.hasMoreElements()

        override fun next(): LibboxIface {
            val raw = src.nextElement()
            return LibboxIface().also {
                it.name = raw.name
                it.index = raw.index
                runCatching { it.mtu = raw.mtu }
                val prefixes = raw.interfaceAddresses.map(::interfaceAddressToPrefixString)
                it.addresses = StringCursor(prefixes.iterator())
            }
        }

        private fun interfaceAddressToPrefixString(addr: InterfaceAddress): String {
            val host = addr.address
            val hostText = if (host is Inet6Address) {
                Inet6Address.getByAddress(host.address).hostAddress
            } else {
                host.hostAddress
            }
            return "$hostText/${addr.networkPrefixLength}"
        }
    }

    private class StringCursor(private val src: Iterator<String>) : StringIterator {
        override fun hasNext(): Boolean = src.hasNext()
        override fun next(): String = src.next()
    }
}
