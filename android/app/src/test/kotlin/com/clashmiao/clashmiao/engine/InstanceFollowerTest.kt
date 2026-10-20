package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 流命令订阅跟随当前内核实例（真机验收 BUG-A）：Dart 一直在监听、没有取消再监听时，内核在
 * 后台停止又启动，原生也必须连到新实例的 command server。
 */
class InstanceFollowerTest {

    private var version = 0L

    private fun snap(status: KernelStatus, attempt: Long, epoch: String = "e1") = KernelSnapshot(
        epoch = epoch,
        version = ++version,
        status = status,
        attempt = attempt,
        desired = Desired.On,
        source = Source.Tile,
        appliedSeq = 1,
        activeConfigRevision = 1,
        lastFailure = null,
        selectionsReplayNeeded = false,
        retainedConfigPaths = emptyList(),
    )

    /** 模拟 StreamBridge：订阅时连一次，之后 follower 说重连就重连。 */
    private fun replay(attachTo: KernelSnapshot?, snapshots: List<KernelSnapshot>): Int {
        val follower = InstanceFollower()
        follower.attach(attachTo)
        var connects = 1
        snapshots.forEach { if (follower.onSnapshot(it)) connects++ }
        return connects
    }

    @Test
    fun `监听期间内核停止再启动 新实例触发一次重连`() {
        val running = snap(KernelStatus.Started, 1)
        val connects = replay(
            running,
            listOf(
                running, // observeForever 订阅即回放当前值：不重连
                snap(KernelStatus.Stopping, 1),
                snap(KernelStatus.Stopped, 1),
                snap(KernelStatus.Starting, 2),
                snap(KernelStatus.Started, 2),
                snap(KernelStatus.Started, 2), // 同一实例的后续快照（重放确认等）
            ),
        )
        assertEquals(2, connects)
    }

    @Test
    fun `订阅时内核没在运行 第一个启动的实例触发重连`() {
        val connects = replay(
            snap(KernelStatus.Starting, 3),
            listOf(snap(KernelStatus.Starting, 3), snap(KernelStatus.Started, 3)),
        )
        assertEquals(2, connects)
    }

    @Test
    fun `网络切换重载 attempt 变化即重连 纪元变化也算新实例`() {
        val follower = InstanceFollower()
        follower.attach(snap(KernelStatus.Started, 4))
        assertTrue(follower.onSnapshot(snap(KernelStatus.Started, 5)))
        assertTrue(follower.onSnapshot(snap(KernelStatus.Started, 5, epoch = "e2")))
        assertFalse(follower.onSnapshot(snap(KernelStatus.Stopped, 5, epoch = "e2")))
        assertFalse(follower.onSnapshot(snap(KernelStatus.Started, 5, epoch = "e2")))
    }
}
