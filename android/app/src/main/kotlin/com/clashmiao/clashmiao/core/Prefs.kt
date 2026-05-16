package com.clashmiao.clashmiao.core

import android.content.Context
import android.content.SharedPreferences
import com.clashmiao.clashmiao.Application
import com.clashmiao.clashmiao.engine.PlainService
import com.clashmiao.clashmiao.engine.TunnelService
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.ObjectInputStream
import java.util.Base64

/**
 * 持久化设置的强类型读写入口。
 *
 * Dart 端通过 `shared_preferences` 插件落盘的所有键都带 `flutter.` 前缀（见 [PrefsKey]），
 * Kotlin 这边要读 Dart 写过去的值时必须用同样的 key。少数纯 Kotlin 内部 cache
 * 不带前缀（例如 [PrefsKey.CACHED_CONFIG_JSON]）。
 *
 * 按调用方组织成几个 group object：
 *   - [Prefs.Profile]：当前激活 profile 路径 / 名字
 *   - [Prefs.Engine]：sing-box 运行模式、debug、内存限制、用户启动标志
 *   - [Prefs.Notice]：通知行为相关
 *   - [Prefs.AppFilter]：per-app proxy 配置
 *
 * 比起以前 [com.clashmiao.clashmiao.Settings] 那种 25 个 var 全平铺在一个 object 上的
 * 写法，调用点读起来语义更清楚（`Prefs.Engine.mode` vs 原本的 `Settings.serviceMode`）。
 */
object Prefs {

    private val sp: SharedPreferences by lazy {
        Application.application.applicationContext.getSharedPreferences(
            "FlutterSharedPreferences",
            Context.MODE_PRIVATE,
        )
    }

    private fun read(key: String, default: String): String =
        sp.getString(key, default) ?: default

    private fun read(key: String, default: Boolean): Boolean = sp.getBoolean(key, default)

    private fun write(key: String, value: String) {
        sp.edit().putString(key, value).apply()
    }

    private fun write(key: String, value: Boolean) {
        sp.edit().putBoolean(key, value).apply()
    }

    // === Profile ==========================================================

    object Profile {
        var activeConfigPath: String
            get() = read(PrefsKey.ACTIVE_CONFIG_PATH, "")
            set(value) = write(PrefsKey.ACTIVE_CONFIG_PATH, value)

        var activeName: String
            get() = read(PrefsKey.ACTIVE_PROFILE_NAME, "")
            set(value) = write(PrefsKey.ACTIVE_PROFILE_NAME, value)

        /**
         * 扫 profile JSON 里有没有 tun inbound —— 决定要不要起 VPN Service。
         * 没读到或解析失败一律返回 false（fail-safe：不起 VPN 总比错起好）。
         */
        fun needsTun(): Boolean {
            val path = activeConfigPath.ifBlank { return false }
            return try {
                val cfg = JSONObject(File(path).readText())
                val inbounds = cfg.getJSONArray("inbounds")
                (0 until inbounds.length()).any { i ->
                    inbounds.getJSONObject(i).optString("type") == "tun"
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    // === Engine ==========================================================

    object Engine {
        var mode: String
            get() = read(PrefsKey.ENGINE_MODE, EngineMode.VPN)
            set(value) = write(PrefsKey.ENGINE_MODE, value)

        var configOptionsJson: String
            get() = read(PrefsKey.CACHED_CONFIG_JSON, "")
            set(value) = write(PrefsKey.CACHED_CONFIG_JSON, value)

        var debugMode: Boolean
            get() = read(PrefsKey.DEBUG_MODE, false)
            set(value) = write(PrefsKey.DEBUG_MODE, value)

        var disableMemoryLimit: Boolean
            get() = read(PrefsKey.DISABLE_MEMORY_LIMIT, false)
            set(value) = write(PrefsKey.DISABLE_MEMORY_LIMIT, value)

        var startedByUser: Boolean
            get() = read(PrefsKey.STARTED_BY_USER, false)
            set(value) = write(PrefsKey.STARTED_BY_USER, value)

        /** 把当前 [mode] 翻译成对应 Service class。 */
        fun serviceClass(): Class<*> = when (mode) {
            EngineMode.VPN -> TunnelService::class.java
            else -> PlainService::class.java
        }

        @Volatile
        private var lastBuiltMode: String? = null

        /**
         * 把当前 mode 跟上一次"已建"的 mode 比较，相同返回 false（不用重建 Service），
         * 不同 cache 当前 mode 并返回 true（caller 应该 stopSelf + 起新 Service）。
         */
        @Synchronized
        fun shouldRebuildService(): Boolean {
            val cur = if (mode == EngineMode.VPN) EngineMode.VPN else EngineMode.PROXY_ONLY
            if (lastBuiltMode == cur) return false
            lastBuiltMode = cur
            return true
        }
    }

    // === Notification ====================================================

    object Notice {
        var dynamic: Boolean
            get() = read(PrefsKey.DYNAMIC_NOTIFICATION, true)
            set(value) = write(PrefsKey.DYNAMIC_NOTIFICATION, value)

        var systemProxyEnabled: Boolean
            get() = read(PrefsKey.SYSTEM_PROXY_ENABLED, true)
            set(value) = write(PrefsKey.SYSTEM_PROXY_ENABLED, value)
    }

    // === Per-app filter ==================================================

    object AppFilter {
        // Dart 端是用 Flutter shared_preferences 的 setStringList 落盘的 ——
        // 它把 List 序列化成 base64 + 加这个 magic 前缀。读出来要先剥前缀再反序列化。
        private const val FLUTTER_LIST_MAGIC = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"

        var mode: String
            get() = read(PrefsKey.APP_FILTER_MODE, AppFilterMode.OFF)
            set(value) = write(PrefsKey.APP_FILTER_MODE, value)

        val enabled: Boolean
            get() = mode != AppFilterMode.OFF

        /** 当前 mode 对应那条白 / 黑名单（INCLUDE / EXCLUDE）。 */
        val effectiveList: List<String>
            get() {
                val key = when (mode) {
                    AppFilterMode.INCLUDE -> PrefsKey.APP_FILTER_INCLUDE
                    AppFilterMode.EXCLUDE -> PrefsKey.APP_FILTER_EXCLUDE
                    else -> return emptyList()
                }
                val raw = read(key, "")
                if (!raw.startsWith(FLUTTER_LIST_MAGIC)) return emptyList()
                return decodeFlutterList(raw.substring(FLUTTER_LIST_MAGIC.length))
            }

        // 内部：Flutter shared_preferences 的 setStringList 编码格式 = MAGIC + base64
        // (Java-serialized List<String>)。用 [java.util.Base64.getMimeDecoder] 因为
        // Flutter 自家编码可能带 line-wrap，MIME decoder 都吃得下；普通 decoder 严格
        // 反而对边界情况炸。这条函数只对 payload 做解码，不读 Android 任何 API ——
        // 单测在 host JVM 直接覆盖（[PrefsListDecoderTest]）。
        internal fun decodeFlutterList(payload: String): List<String> = try {
            val bytes = Base64.getMimeDecoder().decode(payload)
            @Suppress("UNCHECKED_CAST")
            ObjectInputStream(ByteArrayInputStream(bytes)).readObject() as List<String>
        } catch (_: Exception) {
            emptyList()
        }

        /** 公开 magic 前缀给测试 + 文档调用；前缀本身是 Flutter 端硬定的字面量。 */
        internal const val FLUTTER_LIST_MAGIC_PUBLIC = FLUTTER_LIST_MAGIC
    }
}
