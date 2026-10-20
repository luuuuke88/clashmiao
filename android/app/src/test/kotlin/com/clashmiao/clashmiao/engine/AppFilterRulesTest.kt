package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.AppFilterMode
import com.clashmiao.clashmiao.core.Prefs
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.ObjectOutputStream
import java.util.Base64

/** 分应用规则：本 App 始终走隧道（健康探测经 tun 的前提）。 */
class AppFilterRulesTest {

    private val self = "com.clashmiao.clashmiao"

    @Test
    fun `排除名单里有本 App 时滤掉 其余照排`() {
        assertEquals(
            AppFilterPlan.Disallow(listOf("com.a", "com.b")),
            AppFilterRules.forUser(AppFilterMode.EXCLUDE, listOf("com.a", self, "com.b"), self),
        )
    }

    @Test
    fun `排除名单只有本 App 时等于不设规则`() {
        assertEquals(AppFilterPlan.None, AppFilterRules.forUser(AppFilterMode.EXCLUDE, listOf(self), self))
    }

    @Test
    fun `白名单没有本 App 时补上 已有时不重复`() {
        assertEquals(
            AppFilterPlan.Allow(listOf("com.a", self)),
            AppFilterRules.forUser(AppFilterMode.INCLUDE, listOf("com.a"), self),
        )
        assertEquals(
            AppFilterPlan.Allow(listOf(self, "com.a")),
            AppFilterRules.forUser(AppFilterMode.INCLUDE, listOf(self, "com.a"), self),
        )
    }

    @Test
    fun `旧版本 Java 序列化格式恢复出的排除名单含本 App 也滤掉`() {
        val baos = ByteArrayOutputStream()
        ObjectOutputStream(baos).use { it.writeObject(arrayListOf("com.a", self)) }
        val stored = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu" +
            Base64.getEncoder().encodeToString(baos.toByteArray())
        val restored = Prefs.AppFilter.decodeStoredList(stored)
        assertEquals(listOf("com.a", self), restored)

        assertEquals(
            AppFilterPlan.Disallow(listOf("com.a")),
            AppFilterRules.forUser(AppFilterMode.EXCLUDE, restored, self),
        )
    }

    @Test
    fun `当前 JSON 格式恢复出的白名单缺本 App 也补上`() {
        val stored = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu!" + """["com.a","com.b"]"""
        val restored = Prefs.AppFilter.decodeStoredList(stored)
        assertEquals(
            AppFilterPlan.Allow(listOf("com.a", "com.b", self)),
            AppFilterRules.forUser(AppFilterMode.INCLUDE, restored, self),
        )
    }

    @Test
    fun `内核选项 include 优先并补上本 App exclude 滤掉本 App 都空则不设`() {
        assertEquals(
            AppFilterPlan.Allow(listOf("com.a", self)),
            AppFilterRules.forKernel(listOf("com.a"), listOf("com.b"), self),
        )
        assertEquals(
            AppFilterPlan.Disallow(listOf("com.b")),
            AppFilterRules.forKernel(emptyList(), listOf(self, "com.b"), self),
        )
        assertEquals(AppFilterPlan.None, AppFilterRules.forKernel(emptyList(), emptyList(), self))
    }
}
