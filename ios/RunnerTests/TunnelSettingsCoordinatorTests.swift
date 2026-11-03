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

        private var _lost: [String] = []
        var lost: [String] { lock.lock(); defer { lock.unlock() }; return _lost }
        func tunnelSettingsLost(_ reason: String) {
            lock.lock(); _lost.append(reason); lock.unlock()
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

    /// NE 永不回调：等待有上限；之后协调器进入终态，不再有任何提交到达 NE（不会有两个 NE 调用重叠）。
    /// 建 TUN 的超时由启动失败路径收掉隧道，不另行通知。
    func testNonReturningTunSubmitEndsTheSession() {
        let (c, h) = make(tun: 0.3, optional: 0.3)
        h.hold = true
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: c.currentGeneration)) {
            XCTAssertEqual($0 as? TunnelSettingsError, .timedOut)
        }
        h.hold = false
        c.discard() // 重载换代也救不回来
        XCTAssertThrowsError(try c.applyTunSettings(settings(), generation: c.currentGeneration)) {
            XCTAssertEqual($0 as? TunnelSettingsError, .stale)
        }
        XCTAssertEqual(h.calls.count, 1)
        XCTAssertEqual(h.lost, [])
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

    /// 清空那一步 NE 不回调：不再恢复（会与它重叠），收掉隧道。
    func testClearStepTimeoutLosesTunnel() throws {
        let (c, h) = make(optional: 0.3)
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        h.hold = true
        XCTAssertEqual(c.clearDNSCache() as? TunnelSettingsError, .timedOut)
        XCTAssertEqual(h.calls.count, 2, "不在清空悬而未决时发恢复")
        XCTAssertEqual(h.lost.count, 1)
        XCTAssertNil(c.appliedSettings)
        h.calls[1].complete(nil) // 迟到的回调被丢弃
        h.hold = false
        XCTAssertEqual(c.setSystemProxyEnabled(true) as? TunnelSettingsError, .stale)
        XCTAssertEqual(h.calls.count, 2)
    }

    /// 清空那一步被 NE 报错：NE 不保证原设置原样保留，不再恢复（不与之交错），收掉隧道。
    func testClearStepRejectedLosesTunnel() throws {
        struct Boom: Error {}
        let (c, h) = make()
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        h.hold = true
        let clearing = background { _ = c.clearDNSCache() }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 清空
        h.calls[1].complete(Boom())
        wait(for: [clearing], timeout: 5)
        XCTAssertEqual(h.calls.count, 2)
        XCTAssertEqual(h.lost.count, 1)
        XCTAssertNil(c.appliedSettings)
    }

    /// 恢复那一步 NE 不回调：同样收掉隧道。
    func testRestoreTimeoutLosesTunnel() throws {
        let (c, h) = make(optional: 0.3)
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        h.hold = true
        let clearing = background { _ = c.clearDNSCache() }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 清空
        h.calls[1].complete(nil)
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 恢复：不回调
        wait(for: [clearing], timeout: 5)
        XCTAssertEqual(h.lost.count, 1)
        XCTAssertNil(c.appliedSettings)
    }

    /// 代理开关被 NE 报错：缓存不再可信，收掉隧道；成功时才替换缓存。
    func testProxyToggleFailureLosesTunnel() throws {
        struct Boom: Error {}
        let (c, h) = make()
        try c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        XCTAssertNil(c.setSystemProxyEnabled(false))
        XCTAssertEqual(c.appliedSettings?.proxySettings?.httpEnabled, false)
        h.hold = true
        let toggling = background { _ = c.setSystemProxyEnabled(true) }
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // apply
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 关
        XCTAssertEqual(h.submitted.wait(timeout: .now() + 5), .success) // 开：挂起
        h.calls[2].complete(Boom())
        wait(for: [toggling], timeout: 5)
        XCTAssertEqual(h.lost.count, 1)
        XCTAssertNil(c.appliedSettings)
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

    /// 代理开关 NE 不回调：收掉隧道；旧提交迟到生效也不会与任何新提交交错（之后不再提交）。
    func testProxyTimeoutLosesTunnelAndNeverOverlaps() throws {
        let (c, h) = make(optional: 0.3)
        try c.applyTunSettings(settings(proxy: true), generation: c.currentGeneration)
        h.hold = true
        XCTAssertEqual(c.setSystemProxyEnabled(false) as? TunnelSettingsError, .timedOut)
        XCTAssertEqual(h.lost.count, 1)
        h.hold = false
        XCTAssertEqual(c.setSystemProxyEnabled(true) as? TunnelSettingsError, .stale)
        h.calls[1].complete(nil) // 迟到生效
        XCTAssertEqual(h.calls.count, 2, "超时之后没有新的提交")
    }

    /// 清缓存后恢复那一步失败：隧道停在没有设置的状态，收掉隧道（不等别的操作碰巧补救）。
    func testFailedRestoreLosesTunnel() throws {
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
        XCTAssertEqual(h.lost.count, 1)
        XCTAssertNil(c.appliedSettings)
    }

    /// 停止之后发生的失控不通知（隧道已经在收）。
    func testLossAfterStopIsNotReported() throws {
        let (c, h) = make(optional: 0.3)
        try c.applyTunSettings(settings(), generation: c.currentGeneration)
        c.stop()
        XCTAssertEqual(c.clearDNSCache() as? TunnelSettingsError, .stale)
        XCTAssertEqual(h.lost, [])
    }
}
