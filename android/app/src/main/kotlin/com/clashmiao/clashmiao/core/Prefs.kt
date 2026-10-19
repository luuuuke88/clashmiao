package com.clashmiao.clashmiao.core

import android.content.Context
import android.content.SharedPreferences
import com.clashmiao.clashmiao.Application
import com.google.gson.JsonParser
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
        // Dart 端是用 Flutter shared_preferences 的 setStringList 落盘的，值都以这个
        // magic 前缀开头。前缀之后有两种编码（见 [decodeFlutterList]）：
        //   - 当前插件（shared_preferences_android 2.3+）：`!` + JSON 数组；
        //   - 旧版插件：base64(Java 序列化的 List<String>)。
        // 读出来先剥前缀再按格式解码。
        private const val FLUTTER_LIST_MAGIC = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"

        // 插件的 JSON_LIST_PREFIX = LIST_PREFIX + "!"。`!` 不在 base64 字母表里，所以
        // 不会和旧格式的 payload 混淆。
        private const val JSON_LIST_MARKER = "!"

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
                return decodeStoredList(raw)
            }

        /** 解码 Dart setStringList 落盘的完整字符串（含 MAGIC 前缀）；缺省 / 没有前缀 → 空。 */
        internal fun decodeStoredList(raw: String): List<String> {
            if (!raw.startsWith(FLUTTER_LIST_MAGIC)) return emptyList()
            return decodeFlutterList(raw.substring(FLUTTER_LIST_MAGIC.length))
        }

        // 内部：解码剥掉 MAGIC 之后的 payload，两种格式都认：
        //   - `!` + JSON 字符串数组（当前插件写入的格式）。非字符串元素丢弃，与插件
        //     读取平台编码列表时的 filterIsInstance<String>() 一致；
        //   - base64(Java-serialized List<String>)（旧版插件写入、升级前留在磁盘上
        //     的格式）。用 [java.util.Base64.getMimeDecoder] 因为 Flutter 自家编码可能
        //     带 line-wrap，MIME decoder 都吃得下；普通 decoder 严格反而对边界情况炸。
        // 任何格式解不开都返回空 list，不抛。这条函数只对 payload 做解码，不读
        // Android 任何 API —— 单测在 host JVM 直接覆盖（[PrefsListDecoderTest]）。
        internal fun decodeFlutterList(payload: String): List<String> =
            if (payload.startsWith(JSON_LIST_MARKER)) {
                decodeJsonList(payload.substring(JSON_LIST_MARKER.length))
            } else {
                decodeJavaSerializedList(payload)
            }

        private fun decodeJsonList(json: String): List<String> = try {
            JsonParser.parseString(json).asJsonArray.mapNotNull { e ->
                if (e.isJsonPrimitive && e.asJsonPrimitive.isString) e.asString else null
            }
        } catch (_: Exception) {
            emptyList()
        }

        private fun decodeJavaSerializedList(payload: String): List<String> = try {
            val bytes = Base64.getMimeDecoder().decode(payload)
            (ObjectInputStream(ByteArrayInputStream(bytes)).readObject() as List<*>)
                .filterIsInstance<String>()
        } catch (_: Exception) {
            emptyList()
        }

        /** 公开 magic 前缀给测试 + 文档调用；前缀本身是 Flutter 端硬定的字面量。 */
        internal const val FLUTTER_LIST_MAGIC_PUBLIC = FLUTTER_LIST_MAGIC

        /** 同上，JSON 格式在前缀之后的标记。 */
        internal const val JSON_LIST_MARKER_PUBLIC = JSON_LIST_MARKER
    }
}
