package com.clashmiao.clashmiao.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 守住协议契约 —— 这些字符串值都被 Dart 端按字面量解析，改一个就 Android↔Flutter 通信断。
 * 如果有人 IDE refactor 把 enum case 改名了，这层会先红。
 */
class ConstantsTest {

    @Test
    fun `KernelStatus enum case names 必须跟 Dart 解析的字面量一致`() {
        val names = KernelStatus.values().map { it.name }.toSet()
        assertEquals(setOf("Stopped", "Starting", "Started", "Stopping"), names)
    }

    @Test
    fun `AlertCode enum case names 必须跟 Dart BoxAlertType_parse 期望一致`() {
        val names = AlertCode.values().map { it.name }.toSet()
        assertEquals(
            setOf(
                "RequestVPNPermission",
                "RequestNotificationPermission",
                "EmptyConfiguration",
                "StartCommandServer",
                "CreateService",
                "StartService",
            ),
            names,
        )
    }

    @Test
    fun `所有 PrefsKey 普通字段都带 flutter_ 前缀（Dart shared_preferences 约定）`() {
        // 排除 CACHED_CONFIG_JSON —— 它是 Kotlin 内部 cache，不经 Dart prefs，故意无前缀。
        val internalOnly = setOf("config_options_json")
        val keys = listOf(
            PrefsKey.ENGINE_MODE,
            PrefsKey.ACTIVE_CONFIG_PATH,
            PrefsKey.ACTIVE_PROFILE_NAME,
            PrefsKey.APP_FILTER_MODE,
            PrefsKey.APP_FILTER_INCLUDE,
            PrefsKey.APP_FILTER_EXCLUDE,
            PrefsKey.DEBUG_MODE,
            PrefsKey.DISABLE_MEMORY_LIMIT,
            PrefsKey.DYNAMIC_NOTIFICATION,
            PrefsKey.SYSTEM_PROXY_ENABLED,
            PrefsKey.STARTED_BY_USER,
        )
        for (k in keys) {
            assertTrue("$k 应该带 flutter. 前缀", k.startsWith("flutter."))
        }
        assertTrue(PrefsKey.CACHED_CONFIG_JSON in internalOnly)
    }

    @Test
    fun `BroadcastIntents action 字符串使用 app namespace 防止跟系统 intent 撞`() {
        val actions = listOf(
            BroadcastIntents.START,
            BroadcastIntents.SHUTDOWN,
            BroadcastIntents.RELOAD,
        )
        for (a in actions) {
            assertTrue("$a 应该以 com.clashmiao 开头", a.startsWith("com.clashmiao"))
        }
    }

    @Test
    fun `EngineMode 值字符串保留 wire-format（VPN= vpn）`() {
        // VPN mode key 落盘的字符串值是 "vpn"。Settings.serviceMode 读到 "vpn" 才会选 TunnelService。
        assertEquals("vpn", EngineMode.VPN)
        assertEquals("proxy", EngineMode.PROXY_ONLY)
    }

    @Test
    fun `AppFilterMode 三态值不能改`() {
        assertEquals("off", AppFilterMode.OFF)
        assertEquals("include", AppFilterMode.INCLUDE)
        assertEquals("exclude", AppFilterMode.EXCLUDE)
    }
}
