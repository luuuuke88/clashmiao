package com.clashmiao.clashmiao.engine

import com.clashmiao.clashmiao.core.KernelStatus
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Service 形态是请求意图的一部分（真机验收 BUG-3）：由请求 spec 的 options 里 `enable-tun`
 * 决定，而不是另读一个 Dart 从不写的 `service-mode` 偏好。连接中切「仅线路 ↔ VPN」必须真的换类。
 */
class ServiceTypeIntentTest {

    private fun spec(options: String) = LaunchSpec("/cfg/r.json", options, "p", 1)

    @Test
    fun `options 的 enable-tun 决定形态 缺失或无法解析按 VPN`() {
        assertEquals(ServiceType.Vpn, spec("""{"enable-tun":true}""").serviceType())
        assertEquals(ServiceType.Proxy, spec("""{"enable-tun":false,"mixed-port":2080}""").serviceType())
        assertEquals(ServiceType.Vpn, spec("""{"mixed-port":2080}""").serviceType())
        assertEquals(ServiceType.Vpn, spec("""{"enable-tun":"no"}""").serviceType())
        assertEquals(ServiceType.Vpn, spec("not json").serviceType())
        assertEquals(ServiceType.Vpn, spec("").serviceType())
    }

    @Test
    fun `连接中 VPN 切仅线路 新请求换成 Proxy 类 再切回 VPN`() {
        val h = CoreHarness(ServiceType.Vpn, modeFromSpec = true)
        h.tun = true
        h.on(1, rev = 1)
        h.finishJob(JobResult.Started)
        assertEquals(listOf(ServiceType.Vpn), h.all<Effect.StartService>().map { it.type })

        // 切到仅线路：Dart 发出 enable-tun=false 的新请求（新 revision）
        h.tun = false
        h.on(2, rev = 2)
        h.finishTeardown()
        assertEquals(listOf(ServiceType.Vpn, ServiceType.Proxy), h.all<Effect.StartService>().map { it.type })
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 2, desired = Desired.On)

        // 切回 VPN
        h.tun = true
        h.on(3, rev = 3)
        h.finishTeardown()
        assertEquals(
            listOf(ServiceType.Vpn, ServiceType.Proxy, ServiceType.Vpn),
            h.all<Effect.StartService>().map { it.type },
        )
        h.finishJob(JobResult.Started)
        h.assertSnap(status = KernelStatus.Started, rev = 3, desired = Desired.On)
    }

    @Test
    fun `磁贴冷启动按持久化 spec 的形态起 Service`() {
        val h = CoreHarness(ServiceType.Vpn, modeFromSpec = true)
        h.tun = false
        h.external(Source.Tile, Desired.On, fallback = h.spec(7))
        assertEquals(listOf(ServiceType.Proxy), h.all<Effect.StartService>().map { it.type })
    }
}
