package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 持久化 desired / LaunchSpec，以及从旧版 `startedByUser` 与旧配置键的迁移（计划 P2③）。 */
class KernelStoreTest {

    private class MapStore(val map: MutableMap<String, Any?> = mutableMapOf()) : KeyValueStore {
        override fun getString(key: String) = map[key] as String?
        override fun putString(key: String, value: String) {
            map[key] = value
        }

        override fun getBoolean(key: String, default: Boolean) = map[key] as Boolean? ?: default
    }

    private val spec = LaunchSpec("/data/runtime-7.json", "{\"a\":\"b\\\"c\"}", "我的 订阅", 42L)

    @Test
    fun `desired 往返`() {
        val kv = MapStore()
        val s = KernelStore(kv)
        s.saveDesired(Desired.On)
        assertEquals(Desired.On, KernelStore(kv).loadDesired())
        s.saveDesired(Desired.Off)
        assertEquals(Desired.Off, KernelStore(kv).loadDesired())
    }

    @Test
    fun `首次读取 旧键 startedByUser 为 true 迁移成 on 并写回`() {
        val kv = MapStore(mutableMapOf(KernelStore.LEGACY_STARTED_BY_USER to true))
        assertEquals(Desired.On, KernelStore(kv).loadDesired())
        assertEquals("on", kv.map[KernelStore.KEY_DESIRED])
        // 之后旧键再变也不影响
        kv.map[KernelStore.LEGACY_STARTED_BY_USER] = false
        assertEquals(Desired.On, KernelStore(kv).loadDesired())
    }

    @Test
    fun `首次读取 没有任何键 或旧键为 false 都是 off`() {
        assertEquals(Desired.Off, KernelStore(MapStore()).loadDesired())
        val kv = MapStore(mutableMapOf(KernelStore.LEGACY_STARTED_BY_USER to false))
        assertEquals(Desired.Off, KernelStore(kv).loadDesired())
        assertEquals("off", kv.map[KernelStore.KEY_DESIRED])
    }

    @Test
    fun `已有新键时忽略旧键`() {
        val kv = MapStore(
            mutableMapOf(
                KernelStore.KEY_DESIRED to "off",
                KernelStore.LEGACY_STARTED_BY_USER to true,
            ),
        )
        assertEquals(Desired.Off, KernelStore(kv).loadDesired())
    }

    @Test
    fun `LaunchSpec 往返 含引号与中文`() {
        val kv = MapStore()
        KernelStore(kv).saveSpec(spec)
        assertEquals(spec, KernelStore(kv).loadSpec())
    }

    @Test
    fun `没有 spec 时由旧配置键合成 revision 为 0`() {
        val kv = MapStore(
            mutableMapOf(
                KernelStore.LEGACY_ACTIVE_CONFIG_PATH to "/old/config.json",
                KernelStore.LEGACY_ACTIVE_NAME to "老订阅",
                KernelStore.LEGACY_CONFIG_OPTIONS to "{\"x\":1}",
            ),
        )
        assertEquals(
            LaunchSpec("/old/config.json", "{\"x\":1}", "老订阅", 0L),
            KernelStore(kv).loadSpec(),
        )
    }

    @Test
    fun `旧键不全 或什么都没有 返回 null`() {
        assertNull(KernelStore(MapStore()).loadSpec())
        val kv = MapStore(mutableMapOf(KernelStore.LEGACY_ACTIVE_CONFIG_PATH to "/p"))
        assertNull(KernelStore(kv).loadSpec())
    }

    @Test
    fun `新 spec 损坏时回落到旧键 而不是崩溃`() {
        val kv = MapStore(
            mutableMapOf(
                KernelStore.KEY_SPEC to "{not json",
                KernelStore.LEGACY_ACTIVE_CONFIG_PATH to "/old.json",
                KernelStore.LEGACY_CONFIG_OPTIONS to "{}",
            ),
        )
        assertEquals("/old.json", KernelStore(kv).loadSpec()?.runtimeConfigPath)
    }

    @Test
    fun `新 spec 字段缺失视为损坏`() {
        val kv = MapStore(mutableMapOf(KernelStore.KEY_SPEC to "{\"runtimeConfigPath\":\"/p\"}"))
        assertNull(KernelStore(kv).loadSpec())
    }
}
