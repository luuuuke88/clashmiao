package com.clashmiao.clashmiao.core

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import java.util.Base64

/**
 * Flutter shared_preferences setStringList 在 Android 落盘格式：
 *   magic-prefix-string + base64(Java-serialized List<String>)
 *
 * Kotlin 端 [Prefs.AppFilter.decodeFlutterList] 把 base64 部分反过来还原成 List。
 * 这条 test 不用 Robolectric / Application context，把 decoder 当纯函数测：
 *   1. 正常 Flutter 编码 → 正确还原
 *   2. magic 前缀已经被剥掉（[Prefs] 内部先 substring），直接喂 base64 payload
 *   3. 损坏 / 空 / 非法 base64 → 返回空 list 不抛
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

    @Test
    fun `FLUTTER_LIST_MAGIC 前缀字符串值不能改`() {
        // 这是 Flutter 端硬约定的，改了 Android 端立刻读不到老数据。
        assertEquals(
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu",
            Prefs.AppFilter.FLUTTER_LIST_MAGIC_PUBLIC,
        )
    }
}
