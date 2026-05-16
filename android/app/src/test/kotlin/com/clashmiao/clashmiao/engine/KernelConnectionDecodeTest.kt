package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.AlertCode
import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * AIDL 这层把 enum 编码成 int (ordinal) 跨进程传，超出 range 的 int（比如旧版 service
 * 实现端在新版 client 上跑出新枚举值）不能让 client 直接 crash。decodeXxx 必须给
 * fallback。
 */
class KernelConnectionDecodeTest {

    @Test
    fun `decodeStatus 正常 ordinal 还原成对应 enum`() {
        for (s in KernelStatus.values()) {
            assertEquals(s, KernelConnection.decodeStatus(s.ordinal))
        }
    }

    @Test
    fun `decodeStatus 越界 ordinal fallback 到 Stopped`() {
        assertEquals(KernelStatus.Stopped, KernelConnection.decodeStatus(-1))
        assertEquals(KernelStatus.Stopped, KernelConnection.decodeStatus(99))
        assertEquals(KernelStatus.Stopped, KernelConnection.decodeStatus(Int.MAX_VALUE))
    }

    @Test
    fun `decodeAlert 正常 ordinal 还原成对应 enum`() {
        for (a in AlertCode.values()) {
            assertEquals(a, KernelConnection.decodeAlert(a.ordinal))
        }
    }

    @Test
    fun `decodeAlert 越界 ordinal fallback 到 StartService`() {
        assertEquals(AlertCode.StartService, KernelConnection.decodeAlert(-1))
        assertEquals(AlertCode.StartService, KernelConnection.decodeAlert(99))
    }
}
