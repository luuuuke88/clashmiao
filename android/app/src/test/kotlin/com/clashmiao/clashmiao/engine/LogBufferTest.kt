package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LogBufferTest {

    @Test
    fun `append 之后 snapshot 包含那行`() {
        val buf = LogBuffer(capacity = 100)
        buf.append("hello")
        buf.append("world")
        assertEquals(listOf("hello", "world"), buf.snapshot())
    }

    @Test
    fun `超过 capacity 自动丢最旧`() {
        val buf = LogBuffer(capacity = 3)
        buf.append("a")
        buf.append("b")
        buf.append("c")
        buf.append("d")
        assertEquals(listOf("b", "c", "d"), buf.snapshot())
    }

    @Test
    fun `append 触发 subscriber 收到 false`() {
        val buf = LogBuffer(capacity = 10)
        var resetFlag: Boolean? = null
        buf.subscriber = { resetFlag = it }
        buf.append("x")
        assertEquals(false, resetFlag)
    }

    @Test
    fun `reset 触发 subscriber 收到 true 并替换内容`() {
        val buf = LogBuffer(capacity = 10)
        buf.append("old1")
        buf.append("old2")
        var resetFlag: Boolean? = null
        buf.subscriber = { resetFlag = it }
        buf.reset(listOf("new1", "new2", "new3"))
        assertEquals(true, resetFlag)
        assertEquals(listOf("new1", "new2", "new3"), buf.snapshot())
    }

    @Test
    fun `clear 之后 snapshot 是空`() {
        val buf = LogBuffer(capacity = 10)
        buf.append("a")
        buf.append("b")
        buf.clear()
        assertTrue(buf.snapshot().isEmpty())
    }

    @Test
    fun `snapshot 返回的 list 不会随后续 append 变化（隔离）`() {
        val buf = LogBuffer(capacity = 10)
        buf.append("a")
        val snap = buf.snapshot()
        buf.append("b")
        assertEquals(listOf("a"), snap)
        assertEquals(listOf("a", "b"), buf.snapshot())
    }

    @Test
    fun `没设 subscriber 时 append 不抛`() {
        val buf = LogBuffer(capacity = 10)
        assertNull(buf.subscriber)
        buf.append("ok")
        assertFalse(buf.snapshot().isEmpty())
    }
}
