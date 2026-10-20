package com.clashmiao.clashmiao.core

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import java.util.Base64

/**
 * Flutter shared_preferences setStringList 在 Android 落盘格式，两种都要认：
 *   - 当前插件（shared_preferences_android 2.3+，锁定 2.4.27）：
 *     magic-prefix-string + "!" + JSON 字符串数组
 *   - 旧版插件（升级前留在磁盘上的值）：
 *     magic-prefix-string + base64(Java-serialized List<String>)
 *
 * Kotlin 端 [Prefs.AppFilter.decodeStoredList] 剥前缀，[Prefs.AppFilter.decodeFlutterList]
 * 按格式还原成 List。这条 test 不用 Robolectric / Application context，把 decoder
 * 当纯函数测：
 *   1. 两种格式的正常编码 → 正确还原
 *   2. magic 前缀已经被剥掉（[Prefs] 内部先 substring），直接喂 payload
 *   3. 损坏 / 空 / 非法 base64 / 非法 JSON → 返回空 list 不抛
 */
class PrefsListDecoderTest {

    private fun encodeAsFlutterList(items: List<String>): String {
        val baos = ByteArrayOutputStream()
        ObjectOutputStream(baos).use { it.writeObject(items) }
        // Flutter Android 端用 Base64.NO_WRAP 编码 → encoder 默认就是 no-wrap
        return Base64.getEncoder().withoutPadding().encodeToString(baos.toByteArray())
            .let { Base64.getEncoder().encodeToString(baos.toByteArray()) }
    }

    @Test
    fun `正常单项 list 解码还原`() {
        val payload = encodeAsFlutterList(listOf("com.example.app"))
        assertEquals(listOf("com.example.app"), Prefs.AppFilter.decodeFlutterList(payload))
    }

    @Test
    fun `多项 + 中文 + 特殊字符都能还原`() {
        val items = listOf("com.foo", "com.bar", "中文应用", "with space")
        val payload = encodeAsFlutterList(items)
        assertEquals(items, Prefs.AppFilter.decodeFlutterList(payload))
    }

    @Test
    fun `空 list 解码 = 空 list`() {
        val payload = encodeAsFlutterList(emptyList())
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeFlutterList(payload))
    }

    @Test
    fun `垃圾 base64 → 解码失败但不抛，返回空 list`() {
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeFlutterList("not-base64-!!!"))
    }

    @Test
    fun `空字符串 → 空 list`() {
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeFlutterList(""))
    }

    @Test
    fun `合法 base64 但不是 Java-serialized → 空 list`() {
        val plain = Base64.getEncoder().encodeToString("hello world".toByteArray())
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeFlutterList(plain))
    }

    // ── 当前插件格式：MAGIC + "!" + JSON ───────────────────────────────

    private val magic = Prefs.AppFilter.FLUTTER_LIST_MAGIC_PUBLIC

    /** 与插件 Dart 端 `'$jsonListPrefix${jsonEncode(value)}'` 写入的字符串逐字一致。 */
    private fun jsonStored(json: String) = "$magic!$json"

    @Test
    fun `JSON 格式：插件当前写入的完整字符串能还原`() {
        assertEquals(
            listOf("com.example.app", "com.foo.bar"),
            Prefs.AppFilter.decodeStoredList(jsonStored("""["com.example.app","com.foo.bar"]""")),
        )
    }

    @Test
    fun `JSON 格式：中文、空格、引号与反斜杠转义都能还原`() {
        // Dart jsonEncode 对非 ASCII 原样输出，只转义引号与反斜杠。
        val stored = jsonStored("""["中文应用","with space","a\"b\\c"]""")
        assertEquals(
            listOf("中文应用", "with space", "a\"b\\c"),
            Prefs.AppFilter.decodeStoredList(stored),
        )
    }

    @Test
    fun `JSON 格式：空数组 = 空 list`() {
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeStoredList(jsonStored("[]")))
    }

    @Test
    fun `JSON 格式：剥掉 MAGIC 之后直接喂 payload 也认`() {
        assertEquals(listOf("com.a"), Prefs.AppFilter.decodeFlutterList("""!["com.a"]"""))
    }

    @Test
    fun `JSON 格式：非字符串元素丢弃，字符串照常保留`() {
        assertEquals(
            listOf("com.a", "com.b"),
            Prefs.AppFilter.decodeStoredList(jsonStored("""["com.a",1,null,{"x":1},"com.b"]""")),
        )
    }

    @Test
    fun `JSON 格式：损坏的 JSON 或不是数组 → 空 list 不抛`() {
        for (bad in listOf("""["com.a"""", "{}", "\"com.a\"", "", "not json")) {
            assertEquals(bad, emptyList<String>(), Prefs.AppFilter.decodeStoredList(jsonStored(bad)))
        }
    }

    // ── 旧格式与前缀 ──────────────────────────────────────────────────

    @Test
    fun `旧格式：完整字符串（MAGIC + base64 Java 序列化）仍能还原`() {
        val items = listOf("com.legacy", "旧应用")
        assertEquals(items, Prefs.AppFilter.decodeStoredList(magic + encodeAsFlutterList(items)))
    }

    @Test
    fun `没有 MAGIC 前缀或缺省值 → 空 list`() {
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeStoredList(""))
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeStoredList("""["com.a"]"""))
        assertEquals(emptyList<String>(), Prefs.AppFilter.decodeStoredList(magic))
    }

    @Test
    fun `JSON 标记与插件的 JSON_LIST_PREFIX 后缀一致`() {
        // 插件：JSON_LIST_PREFIX = "$LIST_PREFIX!"。`!` 不在 base64 字母表里。
        assertEquals("!", Prefs.AppFilter.JSON_LIST_MARKER_PUBLIC)
    }

    @Test
    fun `FLUTTER_LIST_MAGIC 前缀字符串值不能改`() {
        // 这是 Flutter 端硬约定的，改了 Android 端立刻读不到老数据。
        assertEquals(
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu",
            Prefs.AppFilter.FLUTTER_LIST_MAGIC_PUBLIC,
        )
    }
}
