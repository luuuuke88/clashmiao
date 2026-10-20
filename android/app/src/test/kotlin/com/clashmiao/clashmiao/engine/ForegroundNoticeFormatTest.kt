package com.clashmiao.clashmiao.engine

import org.junit.Assert.assertEquals
import org.junit.Test

/** 通知栏速率文案：十进制单位，个位数取一位小数，其余取整；与官方内核的格式化函数逐档一致。 */
class ForegroundNoticeFormatTest {

    @Test
    fun `零与负数`() {
        assertEquals("0 B", formatBytes(0))
        assertEquals("0 B", formatBytes(-5))
    }

    @Test
    fun `不足 1 kB 也按 kB 表示`() {
        // 与内核的格式化一致：最小单位是 kB，不足 1000 的按小数 kB 写
        assertEquals("0.5 kB", formatBytes(500))
        assertEquals("0.1 kB", formatBytes(50))
        assertEquals("1.0 kB", formatBytes(1_000))
    }

    @Test
    fun `档位与舍入`() {
        assertEquals("1.2 kB", formatBytes(1_234))
        assertEquals("9.9 kB", formatBytes(9_949))
        assertEquals("10 kB", formatBytes(9_950)) // 舍入后 ≥ 10，改为取整
        assertEquals("12 kB", formatBytes(12_345))
        assertEquals("999 kB", formatBytes(999_000))
        assertEquals("1.0 MB", formatBytes(1_000_000))
        assertEquals("1.5 MB", formatBytes(1_500_000))
        assertEquals("125 MB", formatBytes(125_400_000))
        assertEquals("3.2 GB", formatBytes(3_200_000_000L))
        assertEquals("1.0 TB", formatBytes(1_000_000_000_000L))
    }

    @Test
    fun `最大值不越界`() {
        assertEquals("9.2 EB", formatBytes(Long.MAX_VALUE))
    }
}
