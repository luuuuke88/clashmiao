package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.PrefsKey
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser

/** [KernelStore] 依赖的最小键值存储（生产实现是 SharedPreferences，测试用内存 map）。 */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun getBoolean(key: String, default: Boolean): Boolean
}

/**
 * 协调器的持久化：最近一次被受理的 [LaunchSpec] 与 desired（计划 P2③）。
 *
 * 外部入口（磁贴、快捷方式、开机启动）在 App 没打开、Dart 没有给出配置的情况下，
 * 靠这里取回「上一次连接用的配置」。持久化的 desired 取代旧的 `startedByUser`：
 *   - 迁移：`kernel_desired` 不存在时读旧键 `flutter.started_by_user`，为 true 视为 on，并写回新键；
 *   - spec 迁移：没有 `kernel_last_launch_spec` 但旧的 active_config_path / config_options_json 俱在时，
 *     合成 revision=0 的 spec，让旧版本升级上来后磁贴/开机启动仍可用。
 */
class KernelStore(private val kv: KeyValueStore) {

    private val gson = Gson()

    fun loadDesired(): Desired {
        when (kv.getString(KEY_DESIRED)) {
            Desired.On.wire -> return Desired.On
            Desired.Off.wire -> return Desired.Off
        }
        val migrated = if (kv.getBoolean(LEGACY_STARTED_BY_USER, false)) Desired.On else Desired.Off
        kv.putString(KEY_DESIRED, migrated.wire)
        return migrated
    }

    fun saveDesired(desired: Desired) = kv.putString(KEY_DESIRED, desired.wire)

    fun loadSpec(): LaunchSpec? {
        val raw = kv.getString(KEY_SPEC)
        if (raw != null) decode(raw)?.let { return it }
        return legacySpec()
    }

    fun saveSpec(spec: LaunchSpec) = kv.putString(KEY_SPEC, encode(spec))

    internal fun encode(spec: LaunchSpec): String = gson.toJson(
        mapOf(
            "runtimeConfigPath" to spec.runtimeConfigPath,
            "optionsJson" to spec.optionsJson,
            "profileName" to spec.profileName,
            "configRevision" to spec.configRevision,
        ),
    )

    internal fun decode(raw: String): LaunchSpec? = try {
        val o: JsonObject = JsonParser.parseString(raw).asJsonObject
        LaunchSpec(
            runtimeConfigPath = o.get("runtimeConfigPath").asString,
            optionsJson = o.get("optionsJson").asString,
            profileName = o.get("profileName").asString,
            configRevision = o.get("configRevision").asLong,
        )
    } catch (_: Exception) {
        null
    }

    private fun legacySpec(): LaunchSpec? {
        val path = kv.getString(LEGACY_ACTIVE_CONFIG_PATH).orEmpty()
        val options = kv.getString(LEGACY_CONFIG_OPTIONS).orEmpty()
        if (path.isBlank() || options.isBlank()) return null
        return LaunchSpec(
            runtimeConfigPath = path,
            optionsJson = options,
            profileName = kv.getString(LEGACY_ACTIVE_NAME).orEmpty(),
            configRevision = 0L,
        )
    }

    companion object {
        // Kotlin 自己的键：不带 `flutter.` 前缀（Dart 的 shared_preferences 插件不会读到）。
        const val KEY_DESIRED = "kernel_desired"
        const val KEY_SPEC = "kernel_last_launch_spec"

        // 旧版本写入的键，只在迁移时读。
        const val LEGACY_STARTED_BY_USER = PrefsKey.STARTED_BY_USER
        const val LEGACY_ACTIVE_CONFIG_PATH = PrefsKey.ACTIVE_CONFIG_PATH
        const val LEGACY_ACTIVE_NAME = PrefsKey.ACTIVE_PROFILE_NAME
        const val LEGACY_CONFIG_OPTIONS = PrefsKey.CACHED_CONFIG_JSON
    }
}
