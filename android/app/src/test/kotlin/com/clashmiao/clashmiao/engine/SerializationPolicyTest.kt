package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * main 源码不允许再靠 `@SerializedName` 反射编码决定载荷键名：release 包经 R8 混淆，
 * 字段被改名、注解随字段一起被剥掉，Gson 就会按混淆后的名字输出（真机验收 BUG-1：Dart 收到的分组 tag 与 items 全空）。
 * 现在分组 / 统计的线格式由内核（Go）产出并用黄金文件锁定，Kotlin 只透传或解析数字，不再有这类编码；这条策略测试保留，防止回退。
 */
class SerializationPolicyTest {
    @Test
    fun `main 源码不依赖 SerializedName 反射编码`() {
        val root = File("src/main/kotlin")
        assertTrue("找不到源码目录 ${root.absolutePath}", root.isDirectory)
        val offenders = root.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { file ->
                file.readLines().any {
                    it.trimStart().startsWith("@SerializedName") || it.contains("annotations.SerializedName")
                }
            }
            .map { it.relativeTo(root).path }
            .toList()
        assertEquals("这些文件仍靠 @SerializedName 决定载荷键名：$offenders", emptyList<String>(), offenders)
    }
}
