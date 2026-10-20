package com.clashmiao.clashmiao.engine

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import com.clashmiao.clashmiao.core.Prefs
import com.clashmiao.clashmiao.core.asAndroidPrefix
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions

/**
 * VPN 模式下的前台 service。
 *
 * 三个职责，**只**有这三个：
 *   1. 对 Android：是个 [VpnService]，处理 onStart / onBind / onRevoke
 *   2. 对 libbox：是个 [LibboxHost]，sing-box 通过 [openTun] 让我们建 TUN 拿 fd
 *   3. 把生命周期事件交给 [KernelHost]（再上报进程级 [KernelCoordinator]；
 *      是否启动 / 何时停 / 何时退休都由协调器决定，Service 只是被动的载体）
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

    private val host: KernelHost = KernelHost(this, ServiceType.Vpn, libboxHost)

    // === Android Service =================================================

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        host.onStartCommand(intent, flags, startId)

    /** Service 只作为 started service 存在；不再提供 AIDL 绑定，只保留 VpnService 自己的系统绑定。 */
    override fun onBind(intent: Intent): IBinder? = super.onBind(intent)

    override fun onDestroy() {
        host.onDestroy()
        super.onDestroy()
    }

    /**
     * 系统或其他 VPN 撤销了我们的授权。onRevoke 在主线程回调：只上报事件，绝不阻塞
     * （旧实现 runBlocking + withContext(Main) 会死锁成 ANR）。**不**调用 super：
     * 默认实现会立即 stopSelf()，而内核回收与 Service 退休必须由协调器按顺序完成。
     */
    override fun onRevoke() {
        host.onRevoke()
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
        // 防御性纵深：万一 openTun 被二次调用（新代码路径 / 未来重构），先关掉
        // 上一个原始 fd 再覆盖，避免二次遗弃孤儿 tun。正常路径下 tunFd 已为 null。
        host.tunFd?.let { runCatching { it.close() } }
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
        // 本 App 始终走隧道（白名单补上、排除名单滤掉），见 [AppFilterRules]。
        val plan = if (Prefs.AppFilter.enabled) {
            AppFilterRules.forUser(Prefs.AppFilter.mode, Prefs.AppFilter.effectiveList, packageName)
        } else {
            AppFilterRules.forKernel(
                options.includePackage.toList(),
                options.excludePackage.toList(),
                packageName,
            )
        }
        when (plan) {
            is AppFilterPlan.Allow -> plan.packages.forEach { pkg ->
                try {
                    builder.addAllowedApplication(pkg)
                } catch (_: NameNotFoundException) {
                }
            }
            is AppFilterPlan.Disallow -> plan.packages.forEach { pkg ->
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: NameNotFoundException) {
                }
            }
            AppFilterPlan.None -> Unit
        }
    }

    private fun StringIterator.toList(): List<String> {
        val out = ArrayList<String>()
        while (hasNext()) out.add(next())
        return out
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
