package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 事件通道载荷必须与 Dart `KernelSnapshot.fromJson`（B1 报告「事件通道载荷」）逐字段一致。 */
class KernelSnapshotTest {

    @Test
    fun `完整载荷字段名与取值`() {
        val s = KernelSnapshot(
            epoch = "11111111-2222-3333-4444-555555555555",
            version = 12,
            status = KernelStatus.Started,
            attempt = 3,
            desired = Desired.On,
            source = Source.Tile,
            appliedSeq = 7,
            activeConfigRevision = 5,
            lastFailure = KernelFailure(FailureCode.StartTimeout, "", 2, 6),
            selectionsReplayNeeded = false,
        )
        val m = s.toWireMap()
        assertEquals("11111111-2222-3333-4444-555555555555", m["epoch"])
        assertEquals(12L, m["version"])
        assertEquals("started", m["status"])
        assertEquals(3L, m["attempt"])
        assertEquals("on", m["desired"])
        assertEquals("tile", m["source"])
        assertEquals(7L, m["appliedSeq"])
        assertEquals(5L, m["activeConfigRevision"])
        assertEquals(false, m["selectionsReplayNeeded"])
        @Suppress("UNCHECKED_CAST")
        val f = m["lastFailure"] as Map<String, Any?>
        assertEquals(mapOf("code" to "startTimeout", "message" to "", "attempt" to 2L, "seq" to 6L), f)
        assertEquals(
            setOf(
                "epoch", "version", "status", "attempt", "desired", "source", "appliedSeq",
                "activeConfigRevision", "selectionsReplayNeeded", "lastFailure",
            ),
            m.keys,
        )
    }

    @Test
    fun `可空字段以 null 表示`() {
        val m = CoordinatorCore("e", { ServiceType.Vpn }).snapshot.toWireMap()
        assertEquals("stopped", m["status"])
        assertEquals("off", m["desired"])
        assertEquals("system", m["source"])
        assertNull(m["activeConfigRevision"])
        assertNull(m["lastFailure"])
        assertEquals(false, m["selectionsReplayNeeded"])
    }

    @Test
    fun `所有枚举线上值与 Dart 一致`() {
        assertEquals(
            listOf("app", "tile", "shortcut", "boot", "notification", "system"),
            Source.values().map { it.wire },
        )
        assertEquals(
            listOf(
                "startTimeout", "permissionDenied", "emptyConfiguration", "createService",
                "startService", "startCommandServer", "kernelUnresponsive", "kernelExited", "unknown",
            ),
            FailureCode.values().map { it.wire },
        )
        assertEquals(listOf("stale", "wrongEpoch"), RejectReason.values().map { it.wire })
        assertEquals(
            listOf("stopped", "starting", "started", "stopping"),
            KernelStatus.values().map { it.name.lowercase() },
        )
    }
}
