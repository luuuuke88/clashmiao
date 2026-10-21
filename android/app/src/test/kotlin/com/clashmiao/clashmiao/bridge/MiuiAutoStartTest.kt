package com.clashmiao.clashmiao.bridge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 守住 MIUI 自启动状态的两条纯逻辑：「op 返回值 → 状态字符串」与「是否 MIUI / HyperOS」。
 * 状态字符串被 Dart 端按字面量解析，改一个就 Android↔Flutter 通信断。
 */
class MiuiAutoStartTest {

    @Test
    fun `状态字符串字面量与 Dart 解析一致`() {
        assertEquals("unsupported", MiuiAutoStart.UNSUPPORTED)
        assertEquals("allowed", MiuiAutoStart.ALLOWED)
        assertEquals("denied", MiuiAutoStart.DENIED)
        assertEquals("unknown", MiuiAutoStart.UNKNOWN)
    }

    @Test
    fun `MODE_ALLOWED 为 allowed`() {
        assertEquals("allowed", MiuiAutoStart.statusFromOpMode(0))
    }

    @Test
    fun `MODE_IGNORED 与 MODE_ERRORED 为 denied`() {
        assertEquals("denied", MiuiAutoStart.statusFromOpMode(1))
        assertEquals("denied", MiuiAutoStart.statusFromOpMode(2))
    }

    @Test
    fun `含义未定义的取值不编造结论而回 unknown`() {
        for (mode in listOf(3, 4, 5, -1, Int.MAX_VALUE)) {
            assertEquals("mode=$mode", "unknown", MiuiAutoStart.statusFromOpMode(mode))
        }
    }

    @Test
    fun `任一厂商属性非空即视为 MIUI 或 HyperOS`() {
        assertTrue(MiuiAutoStart.isMiuiOrHyperOs("V14", null))
        assertTrue(MiuiAutoStart.isMiuiOrHyperOs("", "OS1.0"))
        assertTrue(MiuiAutoStart.isMiuiOrHyperOs("V14", "OS1.0"))
    }

    @Test
    fun `两个属性都为空或读取失败时视为非 MIUI`() {
        assertFalse(MiuiAutoStart.isMiuiOrHyperOs(null, null))
        assertFalse(MiuiAutoStart.isMiuiOrHyperOs("", ""))
        assertFalse(MiuiAutoStart.isMiuiOrHyperOs("  ", null))
    }

    @Test
    fun `MIUI 私有自启动 op 编号`() {
        assertEquals(10008, MiuiAutoStart.OP_AUTO_START)
    }
}
