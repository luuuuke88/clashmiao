package com.clashmiao.clashmiao.engine

import com.google.gson.JsonParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 分组流载荷与 Dart `OutboundGroup.fromJson` 的契约。
 *
 * release 包经 R8 混淆：反射序列化会按混淆后的字段名（a/b/c/d）输出，`@SerializedName`
 * 随字段一起被剥掉（真机验收 BUG-1 的根因：Dart 收到的分组 tag 与 items 全空）。
 * 所以载荷必须显式写出键名，并且 main 源码里不允许再出现依赖 `@SerializedName` 的反射编码。
 */
class OutboundSnapshotTest {

    @Test
    fun `分组载荷按显式键名编码`() {
        val json = OutboundSnapshot.encode(
            listOf(
                OutboundSnapshot(
                    tag = "select",
                    type = "selector",
                    selected = "auto",
                    items = listOf(
                        OutboundItemSnapshot("auto", "urltest", 0),
                        OutboundItemSnapshot("香港01", "shadowsocks", 128),
                    ),
                ),
            ),
        )
        val group = JsonParser.parseString(json).asJsonArray[0].asJsonObject
        assertEquals(setOf("tag", "type", "selected", "items"), group.keySet())
        assertEquals("select", group["tag"].asString)
        assertEquals("selector", group["type"].asString)
        assertEquals("auto", group["selected"].asString)
        val item = group["items"].asJsonArray[1].asJsonObject
        assertEquals(setOf("tag", "type", "url-test-delay"), item.keySet())
        assertEquals("香港01", item["tag"].asString)
        assertEquals(128, item["url-test-delay"].asInt)
    }

    @Test
    fun `main 源码不依赖 SerializedName 反射编码（R8 会剥掉注解）`() {
        val root = File("src/main/kotlin")
        assertTrue("找不到源码目录 ${root.absolutePath}", root.isDirectory)
        val offenders = root.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { file -> file.readLines().any { it.trimStart().startsWith("@SerializedName") || it.contains("annotations.SerializedName") } }
            .map { it.relativeTo(root).path }
            .toList()
        assertEquals("这些文件仍靠 @SerializedName 决定载荷键名：$offenders", emptyList<String>(), offenders)
    }
}
