import NetworkExtension
import XCTest
@testable import Runner

/// NE 设置提交通道的并发边界：停止与提交的先后、等待上限、reasserting 的持有计数。
final class TunnelSettingsCoordinatorTests: XCTestCase {

    /// 假的 NE：记录每次提交；`hold` 为 true 时不回调，留给测试手动完成（或永不完成）。
    private final class FakeHost: TunnelSettingsHost {
        struct Call { let settings: NEPacketTunnelNetworkSettings?; let complete: (Error?) -> Void }
        private let lock = NSLock()
        private var _calls: [Call] = []
        private var _reasserting: [Bool] = []
        private var _hold = false
        var hold: Bool {
            get { lock.lock(); defer { lock.unlock() }; return _hold }
            set { lock.lock(); _hold = newValue; lock.unlock() }
        }
        let submitted = DispatchSemaphore(value: 0)

        var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }
        var reasserting: [Bool] { lock.lock(); defer { lock.unlock() }; return _reasserting }

        func submitTunnelSettings(_ settings: NEPacketTunnelNetworkSettings?, completion: @escaping (Error?) -> Void) {
            lock.lock()
            _calls.append(Call(settings: settings, complete: completion))
            let hold = _hold
            lock.unlock()
            submitted.signal()
            if !hold { completion(nil) }
        }

        func setReasserting(_ on: Bool) {
            lock.lock(); _reasserting.append(on); lock.unlock()
        }
    }

    private func settings(proxy: Bool = false) -> NEPacketTunnelNetworkSettings {
        let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        if proxy {
            let p = NEProxySettings()
            p.httpServer = NEProxyServer(address: "127.0.0.1", port: 2080)
            p.httpEnabled = true
            s.proxySettings = p
        }
        return s
    }

    private func make(tun: TimeInterval = 5, optional: TimeInterval = 5) -> (TunnelSettingsCoordinator, FakeHost) {
        let c = TunnelSettingsCoordinator(tunTimeout: tun, optionalTimeout: optional)
        let h = FakeHost()
        c.attach(h)
        return (c, h)
    }

    private func background(_ body: @escaping () -> Void) -> XCTestExpectation {
        let done = expectation(description: "background op")
        DispatchQueue.global().async { body(); done.fulfill() }
        return done
    }

    func testApplyRecordsSettingsForCurrentGeneration() throws {
        let (c, h) = make()
        let s = settings()
        try c.applyTunSettings(s, generation: c.currentGeneration)
        XCTAssertEqual(h.calls.count, 1)
        XCTAssertTrue(c.appliedSettings === s)
        c.discard()
        XCTAssertNil(c.appliedSettings)
    }

    func testStaleGenerationNeverReachesNE() {
        let (c, h) = make()
        let gen = c.currentGeneration
        c.discard()
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: gen)) {
            XCTAssertEqual($0 as? TunnelSettingsError, .stale)
        }
        XCTAssertTrue(h.calls.isEmpty)
    }

    /// 停止之后的提交一律不到 NE（复核与发起在同一把锁内，停止也取这把锁）。
    func testNothingReachesNEAfterStop() {
        let (c, h) = make()
        try? c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        let gen = c.currentGeneration
        c.stop()
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: gen))
        XCTAssertEqual(c.clearDNSCache() as? TunnelSettingsError, .stale)
        XCTAssertEqual(c.setSystemProxyEnabled(false) as? TunnelSettingsError, .stale)
        XCTAssertEqual(h.calls.count, 1, "只有停止前那一次")
    }

    /// NE 不回调时，停止立即放行卡在等待里的建 TUN；之后 NE 的迟到回调被丢弃。
    func testStopReleasesInFlightWait() {
        let (c, h) = make(tun: 30)
        h.hold = true
        var thrown: Error?
        let done = background { do { try c.applyTunSettings(self.settings(), generation: 0) } catch { thrown = error } }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success)
        let started = Date()
        c.stop()
        wait(for: [done], timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertEqual(thrown as? TunnelSettingsError, .stale)
        h.calls[0].complete(nil) // 迟到的回调
        XCTAssertNil(c.appliedSettings)
    }

    /// NE 永不回调且没有停止：等待有上限，之后门被释放，后续提交能继续。
    func testNonReturningSubmitTimesOutAndFreesGate() throws {
        let (c, h) = make(tun: 0.3, optional: 0.3)
        h.hold = true
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: c.currentGeneration)) {
            XCTAssertEqual($0 as? TunnelSettingsError, .timedOut)
        }
        h.hold = false
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        XCTAssertEqual(h.calls.count, 2)
    }

    /// 门被一个不返回的可选操作占着时，等门本身也有上限。
    func testGateWaitIsBounded() {
        let (c, h) = make(tun: 0.5, optional: 2)
        try? c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        h.hold = true
        let holder = background { c.setSystemProxyEnabled(false) }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // toggle（持门中）
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: c.currentGeneration)) {
            XCTAssertEqual($0 as? TunnelSettingsError, .busy)
        }
        wait(for: [holder], timeout: 5)
    }

    func testClearDNSCacheClearsThenRestoresUnderReasserting() throws {
        let (c, h) = make()
        let s = settings()
        try c.applyTunSettings(s, generation: c.currentGeneration)
        XCTAssertNil(c.clearDNSCache())
        XCTAssertEqual(h.calls.count, 3)
        XCTAssertNil(h.calls[1].settings)
        XCTAssertTrue(h.calls[2].settings === s)
        XCTAssertEqual(h.reasserting, [true, false])
    }

    /// 清 DNS 先开始、重载随后开始：清 DNS 结束时不得把 reasserting 放回 false（重载还持有），
    /// 且换代后不把旧设置恢复回去。
    func testClearFirstThenReloadKeepsReassertingAndSkipsRestore() throws {
        let (c, h) = make()
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        h.hold = true
        var clearResult: Error?
        let clearing = background { clearResult = c.clearDNSCache() }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 清空那一步，挂起中

        // 重载开始：持有 reasserting、回收本代
        c.beginReasserting()
        c.discard()
        h.calls[1].complete(nil) // 清空迟到完成
        wait(for: [clearing], timeout: 5)

        XCTAssertEqual(clearResult as? TunnelSettingsError, .stale)
        XCTAssertEqual(h.calls.count, 2, "换代后不恢复旧设置")
        XCTAssertEqual(h.reasserting, [true], "清 DNS 结束时重载仍持有 reasserting")

        c.endReasserting()
        XCTAssertEqual(h.reasserting, [true, false])
    }

    /// 失败的重载紧接着取消隧道：不把 reasserting 放回 false；停止之后也不再动它。
    func testReassertingLeftSetOnFailureAndUntouchedAfterStop() {
        let (c, h) = make()
        c.beginReasserting()
        c.endReasserting(leaveSet: true)
        XCTAssertEqual(h.reasserting, [true])
        c.stop()
        c.beginReasserting()
        c.endReasserting()
        XCTAssertEqual(h.reasserting, [true])
    }

    /// 清空那一步超时也要恢复（NE 按调用顺序生效，恢复排在清空之后）。
    func testClearRestoresEvenWhenClearStepTimesOut() throws {
        let (c, h) = make(optional: 0.3)
        let s = settings()
        try c.applyTunSettings(s, generation: c.currentGeneration)
        h.hold = true
        let clearing = background { _ = c.clearDNSCache() }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 清空：不回调
        h.hold = false
        wait(for: [clearing], timeout: 5)
        XCTAssertEqual(h.calls.count, 3)
        XCTAssertTrue(h.calls[2].settings === s)
        XCTAssertEqual(h.reasserting, [true, false])
    }

    func testProxyToggleKeepsCacheOnFailure() throws {
        struct Boom: Error {}
        let (c, h) = make()
        let s = settings(proxy: true)
        try c.applyTunSettings(s, generation: c.currentGeneration)
        h.hold = true
        let toggling = background { _ = c.setSystemProxyEnabled(false) }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success)
        h.calls[1].complete(Boom())
        wait(for: [toggling], timeout: 5)
        XCTAssertTrue(c.appliedSettings === s)
        XCTAssertEqual(c.appliedSettings?.proxySettings?.httpEnabled, true, "失败时原设置未被改动")

        h.hold = false
        XCTAssertNil(c.setSystemProxyEnabled(false))
        XCTAssertEqual(c.appliedSettings?.proxySettings?.httpEnabled, false)
    }

    /// 失败的重载先释放、清 DNS 后释放：reasserting 仍保持（失败保留是粘性的）。
    func testFailedReloadPinsReassertingAcrossHolders() {
        let (c, h) = make()
        c.beginReasserting() // 清 DNS
        c.beginReasserting() // 重载
        c.endReasserting(leaveSet: true) // 重载失败
        c.endReasserting() // 清 DNS 结束
        XCTAssertEqual(h.reasserting, [true])
    }

    /// 关代理的提交超时、NE 之后才迟到生效；再请求「开」时不能凭缓存（仍是开）跳过。
    func testProxyRequestAfterTimeoutIsNotSkipped() throws {
        let (c, h) = make(optional: 0.3)
        try c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        h.hold = true
        XCTAssertEqual(c.setSystemProxyEnabled(false) as? TunnelSettingsError, .timedOut)
        XCTAssertEqual(c.appliedSettings?.proxySettings?.httpEnabled, true, "超时不等于确定未生效，但缓存只记确定的结果")
        h.calls[1].complete(nil) // 迟到生效：系统里代理其实已关
        h.hold = false
        XCTAssertNil(c.setSystemProxyEnabled(true))
        XCTAssertEqual(h.calls.count, 3, "结局不明时照常提交")
        XCTAssertEqual(h.calls[2].settings?.proxySettings?.httpEnabled, true)
        // 收敛后恢复按缓存判定
        XCTAssertNil(c.setSystemProxyEnabled(true))
        XCTAssertEqual(h.calls.count, 3)
    }

    /// 清缓存后恢复那一步失败：系统可能停在清空状态，代理开关之后照常提交完整设置。
    func testFailedRestoreMakesNextToggleSubmit() throws {
        struct Boom: Error {}
        let (c, h) = make()
        try c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        h.hold = true
        let clearing = background { _ = c.clearDNSCache() }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 清空
        h.calls[1].complete(nil)
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 恢复
        h.calls[2].complete(Boom())
        wait(for: [clearing], timeout: 5)
        h.hold = false
        XCTAssertNil(c.setSystemProxyEnabled(true))
        XCTAssertEqual(h.calls.count, 4)
        XCTAssertNotNil(h.calls[3].settings)
    }
}
