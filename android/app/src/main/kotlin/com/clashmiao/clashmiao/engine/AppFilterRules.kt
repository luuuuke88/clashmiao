package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.AppFilterMode

/** 交给 `VpnService.Builder` 的分应用规则（Builder 只接受白名单或排除名单之一）。 */
internal sealed interface AppFilterPlan {
    /** `addAllowedApplication`：只有这些应用走隧道。 */
    data class Allow(val packages: List<String>) : AppFilterPlan

    /** `addDisallowedApplication`：这些应用不走隧道。 */
    data class Disallow(val packages: List<String>) : AppFilterPlan

    /** 不设分应用规则：所有应用都走隧道。 */
    data object None : AppFilterPlan
}

/**
 * 分应用规则的规范化：本 App 始终走隧道。
 *
 * 连接健康探测从本进程直连请求、靠系统把它路由进 tun 来验证 tun 通路（见 Dart 端
 * `connectionHealthProbeProvider`）。本 App 一旦不走隧道，探测就绕过 tun：tun 坏了
 * 而直连能用时漏报，tun 好好的而境外直连不通时误报。所以：
 *   - 白名单模式总是补上本 App；
 *   - 排除名单总是滤掉本 App——包括从旧版本 / 备份恢复出来、含有本 App 的名单。
 * 设置页的应用列表本就不列出本 App（`getInstalledApps`），这里不会和用户能做的选择打架。
 */
internal object AppFilterRules {

    /** 用户在「分应用线路」里设置的规则（[mode] 为 OFF 时调用方不该走到这里）。 */
    fun forUser(mode: String, apps: Collection<String>, self: String): AppFilterPlan =
        when (mode) {
            AppFilterMode.INCLUDE -> AppFilterPlan.Allow(withSelf(apps, self))
            AppFilterMode.EXCLUDE -> disallow(apps, self)
            else -> AppFilterPlan.None
        }

    /** 内核 tun 选项里的 include / exclude 包名（用户没开分应用时）。 */
    fun forKernel(include: List<String>, exclude: List<String>, self: String): AppFilterPlan {
        val incl = clean(include)
        if (incl.isNotEmpty()) return AppFilterPlan.Allow(withSelf(incl, self))
        return disallow(exclude, self)
    }

    private fun disallow(apps: Collection<String>, self: String): AppFilterPlan {
        val list = clean(apps).filter { it != self }
        return if (list.isEmpty()) AppFilterPlan.None else AppFilterPlan.Disallow(list)
    }

    private fun withSelf(apps: Collection<String>, self: String): List<String> =
        (clean(apps) + self).distinct()

    private fun clean(apps: Collection<String>): List<String> =
        apps.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
}
