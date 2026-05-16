package com.clashmiao.clashmiao.core

/**
 * 全部常量集中在这里，按用途分组：
 *   - [BroadcastIntents]：app-internal broadcast 的 action 字符串
 *   - [KernelStatus]：sing-box 内核生命周期状态（值会经 EventChannel 序列化给 Dart）
 *   - [AlertCode]：内核 / VPN 层的非致命错误编码（同样过 EventChannel）
 *   - [AppFilterMode]：per-app proxy 白/黑名单模式
 *   - [EngineMode]：service 形态（纯代理 vs VPN）
 *   - [PrefsKey]：SharedPreferences key 字符串
 *
 * ⚠️ 任何写在 EventChannel 协议里的字符串值都不能改 —— Dart 端按字面量匹配。
 */

object BroadcastIntents {
    const val START = "com.clashmiao.app.SERVICE"
    const val SHUTDOWN = "com.clashmiao.app.SERVICE_CLOSE"
    const val RELOAD = "com.clashmiao.app.sfa.SERVICE_RELOAD"
}

/** sing-box 内核状态。enum case 名直接被 .name 取出走 EventChannel —— 不能改。 */
enum class KernelStatus { Stopped, Starting, Started, Stopping }

/**
 * 内核 / VPN 层抛出来需要让 UI 知道的非致命错误。
 * Dart 侧 `BoxAlertType.parse` 按 `name` 字面量匹配 —— 不能改。
 */
enum class AlertCode {
    RequestVPNPermission,
    RequestNotificationPermission,
    EmptyConfiguration,
    StartCommandServer,
    CreateService,
    StartService,
}

object AppFilterMode {
    const val OFF = "off"
    const val INCLUDE = "include"
    const val EXCLUDE = "exclude"
}

object EngineMode {
    const val PROXY_ONLY = "proxy"
    const val VPN = "vpn"
}

/**
 * SharedPreferences key。`flutter.` 前缀是 shared_preferences 插件硬规定的，
 * Dart `prefs.setString('foo', ...)` 实际写盘 key 是 `flutter.foo`，
 * 所以 Kotlin 这边读 Dart 写的值时必须带前缀。
 */
object PrefsKey {
    private const val FLUTTER = "flutter."

    const val ENGINE_MODE = "${FLUTTER}service-mode"
    const val ACTIVE_CONFIG_PATH = "${FLUTTER}active_config_path"
    const val ACTIVE_PROFILE_NAME = "${FLUTTER}active_profile_name"

    const val APP_FILTER_MODE = "${FLUTTER}per_app_proxy_mode"
    const val APP_FILTER_INCLUDE = "${FLUTTER}per_app_proxy_include_list"
    const val APP_FILTER_EXCLUDE = "${FLUTTER}per_app_proxy_exclude_list"

    const val DEBUG_MODE = "${FLUTTER}debug_mode"
    const val DISABLE_MEMORY_LIMIT = "${FLUTTER}disable_memory_limit"
    const val DYNAMIC_NOTIFICATION = "${FLUTTER}dynamic_notification"
    const val SYSTEM_PROXY_ENABLED = "${FLUTTER}system_proxy_enabled"
    const val STARTED_BY_USER = "${FLUTTER}started_by_user"

    // 这个是 Kotlin 自己 cache 用的，不经 Dart shared_preferences，所以不加前缀。
    const val CACHED_CONFIG_JSON = "config_options_json"
}
