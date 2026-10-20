package com.clashmiao.clashmiao.engine

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import android.system.OsConstants
import com.clashmiao.clashmiao.Application
import com.clashmiao.libcore.core.InterfaceListener
import com.clashmiao.libcore.core.LocalDNS
import com.clashmiao.libcore.core.Platform
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface

/**
 * 自有门面 `Platform` 的 Android 基类。
 *
 * 绝大部分答案在 Android 上是固定的（受 Android API 约束），所以做成 abstract class 把它们 final 住，
 * 子类只需要覆盖跟自己 service 类型相关的几个：[protect]（TunnelService → VpnService.protect）、
 * [openTun]（TunnelService 建 VPN 接口）、[writeLog]。
 *
 * 复杂载荷一律是 JSON 字符串（gomobile 不传 slice / map）：连接归属 `{"uid":N,"packages":[…]}`、
 * 接口列表 `[{name,index,mtu,flags,type,addresses[],dns[],gateway[],metered}]`、TUN 规格见 [TunSpec]。
 */
abstract class CorePlatform : Platform {

    // ===== 固定答案：不可子类改 ==========================================

    final override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    final override fun clearDNSCache() {
        // no-op：内核自己的 DNS 缓存由配置里的缓存选项管
    }

    /** 本地 DNS 走系统解析器（[SystemDnsBridge]）。 */
    final override fun localDNS(): LocalDNS = SystemDnsBridge

    final override fun findOwner(
        protocol: Int,
        srcAddr: String,
        srcPort: Int,
        dstAddr: String,
        dstPort: Int,
    ): String {
        check(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { "android: connection owner lookup needs API 29" }
        val uid = Application.connectivity.getConnectionOwnerUid(
            protocol,
            InetSocketAddress(srcAddr, srcPort),
            InetSocketAddress(dstAddr, dstPort),
        )
        if (uid == Process.INVALID_UID) error("android: connection owner not found")
        val packages = Application.packageManager.getPackagesForUid(uid)?.toList().orEmpty()
        return PlatformJson.owner(uid, packages)
    }

    final override fun startInterfaceMonitor(l: InterfaceListener) {
        NetworkWatcher.attachInterfaceListener(l)
    }

    final override fun stopInterfaceMonitor() {
        NetworkWatcher.attachInterfaceListener(null)
    }

    final override fun interfacesJSON(): String = PlatformJson.interfaces(collectInterfaces())

    // ===== 子类需要 override 的 =========================================

    /** 把出口 socket fd 标记成「不走 VPN tun」，否则内核的出站会被自己的 tun 绕回来。默认 no-op；TunnelService 重写。 */
    override fun protect(fd: Int) {
    }

    override fun openTun(specJSON: String): Int = error("openTun called on a non-VPN service")

    /** 内核日志钩子：每个 Service 必须接到自己持有的 [KernelHost.writeLog]。 */
    abstract override fun writeLog(line: String)

    // ===== 接口列表 =====================================================

    private fun collectInterfaces(): List<PlatformJson.Iface> {
        val connectivity = Application.connectivity
        val metered = HashMap<String, Boolean>()
        val types = HashMap<String, Int>()
        val dns = HashMap<String, List<String>>()
        for (net in connectivity.allNetworks) {
            val link = connectivity.getLinkProperties(net) ?: continue
            val name = link.interfaceName ?: continue
            val caps = connectivity.getNetworkCapabilities(net)
            if (caps != null) {
                metered[name] = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                types[name] = PlatformJson.typeOf(
                    wifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                    cellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                    ethernet = caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET),
                )
            }
            dns[name] = link.dnsServers.mapNotNull { it.hostAddress }
        }
        val out = ArrayList<PlatformJson.Iface>()
        val all = NetworkInterface.getNetworkInterfaces() ?: return out
        for (raw in all) {
            out += PlatformJson.Iface(
                name = raw.name,
                index = raw.index,
                mtu = runCatching { raw.mtu }.getOrDefault(0),
                flags = flagsOf(raw),
                type = types[raw.name] ?: PlatformJson.TYPE_OTHER,
                addresses = raw.interfaceAddresses.map(::prefixOf),
                dns = dns[raw.name].orEmpty(),
                gateway = emptyList(),
                metered = metered[raw.name] ?: false,
            )
        }
        return out
    }

    private fun flagsOf(i: NetworkInterface): Int {
        var f = 0
        if (runCatching { i.isUp }.getOrDefault(false)) f = f or OsConstants.IFF_UP or OsConstants.IFF_RUNNING
        if (runCatching { i.isLoopback }.getOrDefault(false)) f = f or OsConstants.IFF_LOOPBACK
        if (runCatching { i.isPointToPoint }.getOrDefault(false)) f = f or OsConstants.IFF_POINTOPOINT
        if (runCatching { i.supportsMulticast() }.getOrDefault(false)) f = f or OsConstants.IFF_MULTICAST
        return f
    }

    private fun prefixOf(addr: InterfaceAddress): String {
        val host = addr.address
        val text = if (host is Inet6Address) {
            Inet6Address.getByAddress(host.address).hostAddress
        } else {
            host.hostAddress
        }
        return "$text/${addr.networkPrefixLength}"
    }
}

/** 平台回调里的 JSON 载荷（纯函数，JVM 单测直接覆盖）。 */
internal object PlatformJson {
    // 与官方内核的接口类型枚举一致（InterfaceTypeWIFI / Cellular / Ethernet / Other）
    const val TYPE_WIFI = 0
    const val TYPE_CELLULAR = 1
    const val TYPE_ETHERNET = 2
    const val TYPE_OTHER = 3

    fun typeOf(wifi: Boolean, cellular: Boolean, ethernet: Boolean): Int = when {
        wifi -> TYPE_WIFI
        cellular -> TYPE_CELLULAR
        ethernet -> TYPE_ETHERNET
        else -> TYPE_OTHER
    }

    data class Iface(
        val name: String,
        val index: Int,
        val mtu: Int,
        val flags: Int,
        val type: Int,
        val addresses: List<String>,
        val dns: List<String>,
        val gateway: List<String>,
        val metered: Boolean,
    )

    /** `{"uid":N,"packages":[...]}` */
    fun owner(uid: Int, packages: List<String>): String =
        JSONObject().put("uid", uid).put("packages", JSONArray(packages)).toString()

    /** `[{name,index,mtu,flags,type,addresses[],dns[],gateway[],metered}]` */
    fun interfaces(list: List<Iface>): String {
        val arr = JSONArray()
        for (i in list) {
            arr.put(
                JSONObject()
                    .put("name", i.name)
                    .put("index", i.index)
                    .put("mtu", i.mtu)
                    .put("flags", i.flags)
                    .put("type", i.type)
                    .put("addresses", JSONArray(i.addresses))
                    .put("dns", JSONArray(i.dns))
                    .put("gateway", JSONArray(i.gateway))
                    .put("metered", i.metered),
            )
        }
        return arr.toString()
    }
}
