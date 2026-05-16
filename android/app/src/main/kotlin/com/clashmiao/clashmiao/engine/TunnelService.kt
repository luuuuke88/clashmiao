package com.clashmiao.clashmiao.engine

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.core.AppFilterMode
import com.clashmiao.clashmiao.core.asAndroidPrefix
import io.nekohasekai.libbox.TunOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * VPN 模式下的前台 service。
 *
 * 三个职责，**只**有这三个：
 *   1. 对 Android：是个 [VpnService]，处理 onStart / onBind / onRevoke
 *   2. 对 libbox：是个 [LibboxHost]，sing-box 通过 [openTun] 让我们建 TUN 拿 fd
 *   3. 把内核业务全部委托给 [KernelHost]（共用 PlainService 的同一份内核逻辑）
 *
 * 把 TUN 配置过程拆成 5 段小函数（[wireAddresses]、[wireRoutes]、[wireAppFilter]、
 * [wireSystemProxy]），方便单独读 + 后续往里加 strict-route exceptions 之类的
 * 调优时不至于碰到一坨。
 */
class TunnelService : VpnService(), Runnable {

    var systemProxyAvailable = false
        private set
    var systemProxyEnabled = false
        private set

    private val libboxHost: LibboxHost = object : LibboxHost() {
        override fun autoDetectInterfaceControl(fd: Int) {
            // sing-box 让我们把出口 socket fd 标记成 "不走 VPN tun"
            // 否则 sing-box outbound 自己又被自己 tun loop 进来。
            protect(fd)
        }

        override fun openTun(options: TunOptions): Int = buildTunFd(options)

        override fun writeLog(message: String) {
            host.writeLog(message)
        }
    }

    private val host: KernelHost = KernelHost(this, libboxHost)

    // === Android Service =================================================

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        host.onStartCommand(intent, flags, startId)

    override fun onBind(intent: Intent): IBinder {
        // VpnService 自己也想 onBind（系统会调），如果它返回 binder 就让系统赢。
        return super.onBind(intent) ?: host.onBind(intent)
    }

    override fun onDestroy() = host.onDestroy()

    override fun onRevoke() {
        runBlocking { withContext(Dispatchers.Main) { host.onRevoke() } }
    }

    // 占位用，Kotlin 要求至少有个能被外部调到的成员。
    override fun run() = Unit

    // === 给 KernelHost 用的 hook =========================================

    /** sing-box 直接调，TunnelService 收日志后转 IPC fanOut。 */
    fun writeLog(message: String) = host.writeLog(message)

    // === TUN 构建 ========================================================

    private fun buildTunFd(options: TunOptions): Int {
        if (prepare(this) != null) error("android: missing vpn permission")

        val builder = Builder()
            .setSession("sing-box")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        wireAddresses(builder, options)
        if (options.autoRoute) {
            builder.addDnsServer(options.dnsServerAddress)
            wireRoutes(builder, options)
            wireAppFilter(builder, options)
        }
        wireSystemProxy(builder, options)

        val fd = builder.establish()
            ?: error("android: VpnService.Builder.establish() returned null")
        host.tunFd = fd
        return fd.fd
    }

    private fun wireAddresses(builder: Builder, options: TunOptions) {
        val v4 = options.inet4Address
        while (v4.hasNext()) {
            val a = v4.next()
            builder.addAddress(a.address(), a.prefix())
        }
        val v6 = options.inet6Address
        while (v6.hasNext()) {
            val a = v6.next()
            builder.addAddress(a.address(), a.prefix())
        }
    }

    private fun wireRoutes(builder: Builder, options: TunOptions) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            wireRoutesTiramisuPlus(builder, options)
        } else {
            wireRoutesLegacy(builder, options)
        }
    }

    private fun wireRoutesTiramisuPlus(builder: Builder, options: TunOptions) {
        val v4Routes = options.inet4RouteAddress
        if (v4Routes.hasNext()) {
            while (v4Routes.hasNext()) builder.addRoute(v4Routes.next().asAndroidPrefix())
        } else {
            builder.addRoute("0.0.0.0", 0)
        }

        val v6Routes = options.inet6RouteAddress
        if (v6Routes.hasNext()) {
            while (v6Routes.hasNext()) builder.addRoute(v6Routes.next().asAndroidPrefix())
        } else {
            builder.addRoute("::", 0)
        }

        val v4Excl = options.inet4RouteExcludeAddress
        while (v4Excl.hasNext()) builder.excludeRoute(v4Excl.next().asAndroidPrefix())
        val v6Excl = options.inet6RouteExcludeAddress
        while (v6Excl.hasNext()) builder.excludeRoute(v6Excl.next().asAndroidPrefix())
    }

    private fun wireRoutesLegacy(builder: Builder, options: TunOptions) {
        // API < TIRAMISU 没 IpPrefix.excludeRoute，只能 add，且接收的是字符串 + len。
        val v4 = options.inet4RouteRange
        while (v4.hasNext()) {
            val a = v4.next()
            builder.addRoute(a.address(), a.prefix())
        }
        val v6 = options.inet6RouteRange
        while (v6.hasNext()) {
            val a = v6.next()
            builder.addRoute(a.address(), a.prefix())
        }
    }

    private fun wireAppFilter(builder: Builder, options: TunOptions) {
        if (Prefs.AppFilter.enabled) {
            applyUserAppFilter(builder, Prefs.AppFilter.mode, Prefs.AppFilter.effectiveList)
        } else {
            applyFromSingbox(builder, options)
        }
    }

    private fun applyUserAppFilter(builder: Builder, mode: String, apps: Collection<String>) {
        if (mode == AppFilterMode.INCLUDE) {
            for (pkg in apps) runCatching { builder.addAllowedApplication(pkg) }
            // INCLUDE 时 clashmiao 本进程必须自己也走 VPN，否则 sing-box 自己拨号都被切。
            // 等等：自己走 VPN 反而会 loop，应该 disallow。但 hiddify 历史代码就这样，
            // 实际 sing-box outbound socket 走 protect() 不会 loop，所以加进去是 OK 的。
            runCatching { builder.addAllowedApplication(packageName) }
        } else {
            for (pkg in apps) runCatching { builder.addDisallowedApplication(pkg) }
        }
    }

    private fun applyFromSingbox(builder: Builder, options: TunOptions) {
        val incl = options.includePackage
        while (incl.hasNext()) {
            try {
                builder.addAllowedApplication(incl.next())
            } catch (_: NameNotFoundException) {
            }
        }
        val excl = options.excludePackage
        while (excl.hasNext()) {
            try {
                builder.addDisallowedApplication(excl.next())
            } catch (_: NameNotFoundException) {
            }
        }
    }

    private fun wireSystemProxy(builder: Builder, options: TunOptions) {
        if (!options.isHTTPProxyEnabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            systemProxyAvailable = false
            systemProxyEnabled = false
            return
        }
        systemProxyAvailable = true
        systemProxyEnabled = Prefs.Notice.systemProxyEnabled
        if (systemProxyEnabled) {
            builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(options.httpProxyServer, options.httpProxyServerPort),
            )
        }
    }
}
