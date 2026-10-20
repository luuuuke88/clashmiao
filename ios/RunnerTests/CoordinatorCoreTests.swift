import XCTest
@testable import Runner

/// `CoordinatorCore` 的行为测试。核心是纯状态机：用一个把动作记下来的小壳驱动它，不需要真实时钟、线程或 NE。
final class CoordinatorCoreTests: XCTestCase {

    // MARK: - 测试壳

    /// 记录所有动作的驱动壳；`tokens` 方法按种类取出最近派发的任务 token。
    final class Harness {
        let core: CoordinatorCore
        var effects: [Effect] = []
        var launchIds: [String] = []
        private var launchSeq = 0

        init(storedSpec: LaunchSpec? = nil, reloadOnNetworkChange: Bool = false) {
            var cfg = CoordinatorCore.Config()
            cfg.reloadOnNetworkChange = reloadOnNetworkChange
            var counter = 0
            core = CoordinatorCore(
                epoch: "epoch-0001", config: cfg, storedSpec: storedSpec,
                makeLaunchId: { counter += 1; return "launch-\(counter)" }
            )
        }

        @discardableResult
        func apply(_ step: CoreStep) -> Receipt? {
            effects.append(contentsOf: step.effects)
            return step.receipt
        }

        var snap: KernelSnapshot { core.snapshot }

        func lastConnect() -> (token: Int64, spec: LaunchSpec, launchId: String)? {
            for e in effects.reversed() {
                if case .runConnect(let t, let s, let l) = e { return (t, s, l) }
            }
            return nil
        }
        func lastReload() -> (token: Int64, spec: LaunchSpec, launchId: String)? {
            for e in effects.reversed() {
                if case .runReload(let t, let s, let l, _) = e { return (t, s, l) }
            }
            return nil
        }
        func lastTeardown() -> Int64? {
            for e in effects.reversed() {
                if case .runTeardown(let t) = e { return t }
            }
            return nil
        }
        func count(_ matches: (Effect) -> Bool) -> Int { effects.filter(matches).count }
        func clearEffects() { effects.removeAll() }

        func request(seq: Int64, _ d: Desired, spec: LaunchSpec? = nil, epoch: String = "epoch-0001") -> Receipt? {
            apply(core.onRequest(epoch: epoch, seq: seq, desired: d, launch: spec, reason: "test"))
        }
        func tunnel(_ s: TunnelStatus, _ r: ExtensionState? = nil) { apply(core.onTunnelStatus(s, report: r)) }
        func finish(_ token: Int64, _ r: JobResult) { apply(core.onJobFinished(token: token, result: r)) }
        func timer(_ k: TimerKey) { apply(core.onTimer(k)) }
    }

    func spec(_ rev: Int64, path: String? = nil) -> LaunchSpec {
        LaunchSpec(runtimeConfigPath: path ?? "/rt/runtime-\(rev).json", optionsJson: "{}", profileName: "p", configRevision: rev)
    }

    func running(_ launchId: String, rev: Int64, session: String = "S1", gen: Int = 1) -> ExtensionState {
        ExtensionState(sessionId: session, launchId: launchId, phase: .running, generation: gen, revision: rev)
    }

    func stopped(_ launchId: String, session: String = "S1", reason: Int = 1) -> ExtensionState {
        ExtensionState(sessionId: session, launchId: launchId, phase: .stopped, stopReason: reason)
    }

    /// 把核心推到「rev 已 started」的稳态；返回此时的 launchId。
    @discardableResult
    func bringUp(_ h: Harness, seq: Int64 = 1, rev: Int64 = 1) -> String {
        h.tunnel(.disconnected)
        _ = h.request(seq: seq, .on, spec: spec(rev))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        h.tunnel(.connected, running(c.launchId, rev: rev))
        return c.launchId
    }

    // MARK: - 请求受理

    func testConnectHappyPath() {
        let h = Harness()
        h.tunnel(.disconnected)
        let r = h.request(seq: 1, .on, spec: spec(1))
        XCTAssertEqual(r, Receipt(accepted: true, reason: nil, epoch: "epoch-0001", appliedSeq: 1))
        XCTAssertEqual(h.snap.status, .starting)
        XCTAssertEqual(h.snap.attempt, 1)
        XCTAssertEqual(h.snap.source, .app)
        let c = h.lastConnect()!
        XCTAssertEqual(c.spec, spec(1))
        // 提交后、隧道就绪前仍是 starting。
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        XCTAssertEqual(h.snap.status, .starting)
        h.tunnel(.connected, running(c.launchId, rev: 1))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.activeConfigRevision, 1)
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
        XCTAssertNil(h.snap.lastFailure)
    }

    func testStaleAndWrongEpochDoNotChangeState() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 5, .on, spec: spec(1))
        let before = h.snap
        let stale = h.request(seq: 5, .off)
        XCTAssertEqual(stale?.accepted, false)
        XCTAssertEqual(stale?.reason, .stale)
        let wrong = h.request(seq: 6, .off, epoch: "other")
        XCTAssertEqual(wrong?.reason, .wrongEpoch)
        XCTAssertEqual(wrong?.appliedSeq, 5)
        XCTAssertEqual(h.snap, before)
    }

    func testRapidOnOffOnEndsStartedWithoutFailure() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let first = h.lastConnect()!
        _ = h.request(seq: 2, .off)
        _ = h.request(seq: 3, .on, spec: spec(1))
        // 第一个 Connect 在 off 时已被打上取消标；它在取消点返回后，才轮到最后一个意图的 Connect。
        XCTAssertEqual(h.count { if case .runConnect = $0 { return true }; return false }, 1)
        h.finish(first.token, .cancelled)
        XCTAssertEqual(h.count { if case .runConnect = $0 { return true }; return false }, 2)
        XCTAssertNil(h.snap.lastFailure, "取消不是失败")
        let second = h.lastConnect()!
        h.finish(second.token, .launched)
        h.tunnel(.connected, running(second.launchId, rev: 1))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.appliedSeq, 3)
        XCTAssertEqual(h.snap.desired, .on)
    }

    func testOffWhileConnectJobInFlightCancelsAndDoesNotStartTunnel() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        _ = h.request(seq: 2, .off)
        XCTAssertEqual(h.count { if case .cancelJob(let t) = $0 { return t == c.token }; return false }, 1)
        XCTAssertEqual(h.snap.status, .stopping, "任务还没返回，不能谎报 stopped")
        h.finish(c.token, .cancelled)
        XCTAssertEqual(h.snap.status, .stopped)
        XCTAssertNil(h.lastTeardown(), "取消发生在提交之前，没有隧道需要停")
    }

    func testOffAfterSubmittedConnectTearsTunnelDown() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        _ = h.request(seq: 2, .off)
        let t = h.lastTeardown()!
        XCTAssertEqual(h.snap.status, .stopping)
        h.finish(t, .tornDown)
        XCTAssertEqual(h.snap.status, .stopping, "提交 stop 不等于已停止")
        h.tunnel(.disconnecting)
        h.tunnel(.disconnected, stopped(c.launchId))
        XCTAssertEqual(h.snap.status, .stopped)
        XCTAssertNil(h.snap.lastFailure)
        XCTAssertEqual(h.snap.desired, .off)
    }

    // MARK: - 放弃的启动（提交了却不可见）

    func testAbandonedStartFailsAndLateConnectingIsNotAdoptedAsExternal() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .abandoned(.startService, "tunnel did not start"))
        XCTAssertEqual(h.snap.lastFailure?.code, .startService)
        XCTAssertEqual(h.snap.desired, .off)
        // 迟到的启动终于冒出来：它属于我们那次被放弃的启动，不是外部启动。
        h.clearEffects()
        h.tunnel(.connecting)
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertEqual(h.snap.source, .app)
        XCTAssertNotNil(h.lastTeardown(), "迟到的启动要被停掉")
    }

    func testAdoptGuardExpiresAndThenExternalStartIsAdoptedAgain() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        h.finish(h.lastConnect()!.token, .abandoned(.startService, "x"))
        h.timer(TimerKey(.adoptGuard))
        h.tunnel(.connecting)
        XCTAssertEqual(h.snap.desired, .on)
        XCTAssertEqual(h.snap.source, .system)
    }

    // MARK: - 失败归属

    func testConnectFailureWritesFailureForCurrentSeqAndTurnsOff() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .failed(.permissionDenied, "denied"))
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertEqual(h.snap.lastFailure, KernelFailure(code: .permissionDenied, message: "denied", attempt: 1, seq: 1))
        XCTAssertEqual(h.snap.status, .stopped)
    }

    func testStaleJobFailureDoesNotTouchNewRequest() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let old = h.lastConnect()!
        // 意图换成 rev 2：旧 Connect 被取消；新请求有自己的序列。
        _ = h.request(seq: 2, .on, spec: spec(2))
        XCTAssertEqual(h.count { if case .cancelJob(let t) = $0 { return t == old.token }; return false }, 1)
        h.finish(old.token, .failed(.createService, "boom"))
        XCTAssertEqual(h.snap.desired, .on, "过时执行的失败不能把新请求置 off")
        XCTAssertNil(h.snap.lastFailure)
    }

    func testStartTimeoutFailsCurrentRequest() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        h.timer(TimerKey(.startTimeout, subject: 1))
        XCTAssertEqual(h.snap.lastFailure?.code, .startTimeout)
        XCTAssertEqual(h.snap.lastFailure?.seq, 1)
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertNotNil(h.lastTeardown(), "超时后要把半起的隧道停掉")
    }

    func testExtensionReportedFailureIsMappedWithItsCode() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        h.tunnel(.disconnected, ExtensionState(sessionId: "S1", launchId: c.launchId, phase: .failed, code: .createService, message: "bad config"))
        XCTAssertEqual(h.snap.lastFailure?.code, .createService)
        XCTAssertEqual(h.snap.lastFailure?.message, "bad config")
        XCTAssertEqual(h.snap.desired, .off)
    }

    func testDisconnectedBeforeSubmitIsNoise() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        // Connect 尚未提交时到达的 disconnected（重复的初始状态）不是启动失败。
        h.tunnel(.disconnected)
        XCTAssertNil(h.snap.lastFailure)
        XCTAssertEqual(h.snap.desired, .on)
    }

    // MARK: - 收敛 / 重载

    func testSameRevisionWhileStartedIsNoOp() {
        let h = Harness()
        bringUp(h)
        h.clearEffects()
        _ = h.request(seq: 2, .on, spec: spec(1))
        XCTAssertNil(h.lastReload())
        XCTAssertNil(h.lastConnect())
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.attempt, 1)
    }

    func testRevisionChangeReloadsInPlaceAndBumpsAttempt() {
        let h = Harness()
        bringUp(h)
        h.clearEffects()
        _ = h.request(seq: 2, .on, spec: spec(2))
        let r = h.lastReload()!
        XCTAssertEqual(r.spec, spec(2))
        XCTAssertNil(h.lastTeardown(), "重载不断开 VPN")
        XCTAssertEqual(h.snap.status, .starting)
        XCTAssertEqual(h.snap.attempt, 2)
        XCTAssertFalse(h.snap.selectionsReplayNeeded)
        h.tunnel(.reasserting, running("launch-1", rev: 1)) // 自己的重载期间
        h.finish(r.token, .reloaded(sessionId: "S1", generation: 2))
        h.tunnel(.connected, running(r.launchId, rev: 2, gen: 2))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.activeConfigRevision, 2)
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
        XCTAssertEqual(h.snap.attempt, 2)
    }

    func testReloadFailureTurnsOffAndStopsTunnel() {
        let h = Harness()
        bringUp(h)
        _ = h.request(seq: 2, .on, spec: spec(2))
        let r = h.lastReload()!
        h.finish(r.token, .failed(.startService, "reload failed"))
        XCTAssertEqual(h.snap.lastFailure?.code, .startService)
        XCTAssertEqual(h.snap.lastFailure?.seq, 2)
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertNotNil(h.lastTeardown())
    }

    func testAckReplayIsIdempotentAndIgnoresOtherAttempts() {
        let h = Harness()
        bringUp(h)
        h.apply(h.core.onAckReplay(99))
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
        h.apply(h.core.onAckReplay(1))
        XCTAssertFalse(h.snap.selectionsReplayNeeded)
        let v = h.snap.version
        h.apply(h.core.onAckReplay(1))
        XCTAssertEqual(h.snap.version, v, "幂等：不再产生新版本")
    }

    func testDesiredOnWhileTunnelDisconnectingWaitsThenConnects() {
        let h = Harness()
        let id = bringUp(h)
        _ = h.request(seq: 2, .off)
        let t = h.lastTeardown()!
        h.finish(t, .tornDown)
        h.tunnel(.disconnecting)
        h.clearEffects()
        _ = h.request(seq: 3, .on, spec: spec(1))
        XCTAssertNil(h.lastConnect(), "disconnecting 期间启动会失败，必须等 disconnected")
        h.tunnel(.disconnected, stopped(id))
        XCTAssertNotNil(h.lastConnect())
        XCTAssertEqual(h.snap.attempt, 2)
    }

    // MARK: - 外部变化

    func testExternalStartIsAdoptedAsSystemSource() {
        let h = Harness(storedSpec: spec(7))
        h.tunnel(.disconnected)
        h.tunnel(.connecting)
        XCTAssertEqual(h.snap.desired, .on)
        XCTAssertEqual(h.snap.source, .system)
        XCTAssertNil(h.lastConnect(), "外部启动不能被我们再起一次")
        h.tunnel(.connected, running("ext", rev: 7))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.activeConfigRevision, 7)
        XCTAssertEqual(h.snap.attempt, 1)
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
    }

    func testColdAttachToRunningTunnelWithoutStoredSpec() {
        let h = Harness()
        h.tunnel(.connected, running("ext", rev: 3))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.desired, .on)
        XCTAssertEqual(h.snap.source, .system)
        XCTAssertEqual(h.snap.activeConfigRevision, 3)
        XCTAssertNil(h.snap.lastFailure)
        XCTAssertNil(h.lastTeardown(), "不能因为没有 spec 就把用户正在用的隧道拆掉")
        // Dart 随后以 rev 4 请求：就地重载。
        _ = h.request(seq: 1, .on, spec: spec(4))
        XCTAssertNotNil(h.lastReload())
    }

    func testOwnLaunchIsNotMistakenForExternalStart() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        // 状态事件先于任务结果到达。
        h.tunnel(.connecting)
        h.tunnel(.connected, running(c.launchId, rev: 1))
        h.finish(c.token, .launched)
        XCTAssertEqual(h.snap.source, .app)
        XCTAssertEqual(h.snap.attempt, 1)
        XCTAssertEqual(h.snap.status, .started)
    }

    func testSystemSettingsTurnedVpnOffIsNotAFailure() {
        let h = Harness()
        let id = bringUp(h)
        h.tunnel(.disconnecting, stopped(id))
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertEqual(h.snap.source, .system)
        h.tunnel(.disconnected, stopped(id))
        XCTAssertEqual(h.snap.status, .stopped)
        XCTAssertNil(h.snap.lastFailure)
        XCTAssertNil(h.lastTeardown())
    }

    func testExtensionKilledWithoutStopRecordIsKernelExited() {
        let h = Harness()
        let id = bringUp(h)
        h.tunnel(.disconnected, running(id, rev: 1))
        XCTAssertEqual(h.snap.lastFailure?.code, .kernelExited)
        XCTAssertTrue(h.snap.lastFailure?.message.contains("memory") ?? false)
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertEqual(h.snap.status, .stopped)
    }

    func testExternalReloadIsDetectedByGenerationNotByReasserting() {
        let h = Harness()
        let id = bringUp(h)
        h.apply(h.core.onAckReplay(1))
        // 后台完整发生的重载：我们没看到 reasserting，只在 connected 时看到 generation 变大。
        h.tunnel(.connected, running(id, rev: 1, gen: 2))
        XCTAssertEqual(h.snap.attempt, 2)
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
        XCTAssertNil(h.lastReload(), "外部重载不需要我们再重载")
    }

    func testReassertingWithoutGenerationChangeKeepsAttemptButShowsStarting() {
        let h = Harness()
        let id = bringUp(h)
        h.tunnel(.reasserting, running(id, rev: 1))
        XCTAssertEqual(h.snap.attempt, 1, "clearDNSCache 也会触发 reasserting，不能据此分配 attempt")
        XCTAssertEqual(h.snap.status, .starting)
        XCTAssertNil(h.lastReload(), "不能把 DNS 刷新当成 revision 不符去重载")
        h.tunnel(.connected, running(id, rev: 1))
        XCTAssertEqual(h.snap.status, .started)
        XCTAssertEqual(h.snap.attempt, 1)
    }

    func testSessionChangeWithoutSeeingDownIsRebased() {
        let h = Harness()
        let id = bringUp(h)
        h.apply(h.core.onAckReplay(1))
        h.tunnel(.connected, running(id, rev: 1, session: "S2", gen: 1))
        XCTAssertEqual(h.snap.attempt, 2)
        XCTAssertTrue(h.snap.selectionsReplayNeeded)
        XCTAssertEqual(h.core.liveInstance?.sessionId, "S2")
    }

    func testRebasedKernelWithUnknownSpecMakesRetainedPathsUnknown() {
        let h = Harness(storedSpec: spec(1))
        h.tunnel(.connected, running("ext", rev: 9))
        XCTAssertNil(h.snap.retainedConfigPaths, "不知道正在跑的是哪份 runtime 配置：Dart 一个都不能删")
        XCTAssertEqual(h.snap.status, .started)
    }

    func testLiveInstanceIsOnlyAvailableWhenStarted() {
        let h = Harness()
        XCTAssertNil(h.core.liveInstance)
        let id = bringUp(h)
        XCTAssertEqual(h.core.liveInstance?.attempt, 1)
        XCTAssertEqual(h.core.liveInstance?.generation, 1)
        _ = h.request(seq: 2, .on, spec: spec(2))
        XCTAssertNil(h.core.liveInstance, "重载派发后栅栏必须已清空")
        _ = id
    }

    // MARK: - stopReason 分类 / invalid / 缺失 state

    func testFailureStopReasonsAreFailuresOthersAreSystemOff() {
        for (reason, isFailure) in [(2, true), (7, true), (14, true), (1, false), (5, false), (9, false), (11, false), (99, false)] {
            let h = Harness()
            let id = bringUp(h)
            h.tunnel(.disconnected, stopped(id, reason: reason))
            if isFailure {
                XCTAssertEqual(h.snap.lastFailure?.code, .kernelExited, "reason \(reason)")
            } else {
                XCTAssertNil(h.snap.lastFailure, "reason \(reason)")
                XCTAssertEqual(h.snap.source, .system, "reason \(reason)")
            }
            XCTAssertEqual(h.snap.desired, .off)
            XCTAssertEqual(h.snap.status, .stopped)
        }
    }

    func testInvalidStatusIsTreatedAsDown() {
        let h = Harness()
        let id = bringUp(h)
        h.tunnel(.invalid, stopped(id, reason: 10))
        XCTAssertEqual(h.snap.status, .stopped)
        XCTAssertEqual(h.snap.desired, .off)
    }

    func testMissingStateWhileRunningIsKernelExited() {
        let h = Harness()
        bringUp(h)
        h.tunnel(.disconnected, nil)
        XCTAssertEqual(h.snap.lastFailure?.code, .kernelExited)
        XCTAssertEqual(h.snap.status, .stopped)
    }

    func testMissingStateWhileStartingIsStartServiceFailure() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        h.tunnel(.disconnected, nil)
        XCTAssertEqual(h.snap.lastFailure?.code, .startService)
    }

    // MARK: - 旧停止结果不得覆盖新的 on 请求（C1）

    func testStoppedReportDuringExpectedTeardownDoesNotOverrideNewOn() {
        let h = Harness()
        let id = bringUp(h)
        _ = h.request(seq: 2, .off)
        h.finish(h.lastTeardown()!, .tornDown)
        _ = h.request(seq: 3, .on, spec: spec(1))
        h.tunnel(.disconnecting, stopped(id))
        XCTAssertEqual(h.snap.desired, .on, "预期中的停止不能被当成系统关闭")
        h.tunnel(.disconnected, stopped(id))
        XCTAssertEqual(h.snap.desired, .on)
        XCTAssertEqual(h.snap.source, .app)
        XCTAssertNil(h.snap.lastFailure)
        XCTAssertNotNil(h.lastConnect())
    }

    func testLateConnectedAfterCancelledStartIsNotAdopted() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.finish(c.token, .launched)
        h.tunnel(.connecting)
        _ = h.request(seq: 2, .off)
        h.finish(h.lastTeardown()!, .tornDown)
        // 停止已提交，但启动在最后一刻还是走到了 connected：不能当作外部启动接管。
        h.tunnel(.connected, running(c.launchId, rev: 1))
        XCTAssertEqual(h.snap.desired, .off)
        XCTAssertEqual(h.snap.source, .app)
        h.tunnel(.disconnected, stopped(c.launchId))
        XCTAssertEqual(h.snap.status, .stopped)
        XCTAssertNil(h.snap.lastFailure)
    }

    func testResetTunnelRequestsReloadOfSameConfig() {
        let h = Harness()
        bringUp(h)
        h.apply(h.core.onReloadRequested(.app))
        let r = h.lastReload()!
        XCTAssertEqual(r.spec, spec(1))
        XCTAssertEqual(h.snap.attempt, 2)
    }

    // MARK: - 停止无响应

    func testTeardownBlockedTriggersKernelUnresponsiveAndKeepsStopping() {
        let h = Harness()
        bringUp(h)
        _ = h.request(seq: 2, .off)
        let t = h.lastTeardown()!
        h.finish(t, .tornDown)
        h.timer(TimerKey(.stopWatchdog, subject: 1))
        XCTAssertEqual(h.snap.lastFailure?.code, .kernelUnresponsive)
        XCTAssertEqual(h.snap.lastFailure?.seq, 2)
        XCTAssertEqual(h.snap.status, .stopping, "如实保持 stopping")
        // 重发 off：结果归新请求，并重新提交停止。
        h.clearEffects()
        _ = h.request(seq: 3, .off)
        XCTAssertEqual(h.snap.lastFailure?.seq, 3)
        XCTAssertNotNil(h.lastTeardown())
    }

    func testJobWatchdogOnStartFailsCurrentExec() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.apply(h.core.onJobStep(token: c.token, name: "buildConfig"))
        h.timer(TimerKey(.watchdog, subject: c.token, serial: 1))
        XCTAssertEqual(h.snap.lastFailure?.code, .kernelUnresponsive)
        XCTAssertEqual(h.snap.desired, .off)
    }

    func testAuthorizeStepHasNoWatchdog() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(1))
        let c = h.lastConnect()!
        h.clearEffects()
        h.apply(h.core.onJobStep(token: c.token, name: CoordinatorCore.authorizeStep))
        XCTAssertEqual(h.count { if case .setTimer = $0 { return true }; return false }, 0)
        XCTAssertEqual(h.count { if case .cancelTimer = $0 { return true }; return false }, 1)
    }

    // MARK: - 持久化与配置引用

    func testRetainedPathsIncludeIntentStoredActiveAndUnconfirmed() {
        let h = Harness(storedSpec: spec(1, path: "/rt/old.json"))
        XCTAssertEqual(h.snap.retainedConfigPaths, ["/rt/old.json"])
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: spec(2, path: "/rt/new.json"))
        // 新路径已在意图里，旧的已确认路径仍声明，新的未确认路径也声明。
        XCTAssertEqual(h.snap.retainedConfigPaths, ["/rt/new.json", "/rt/old.json"])
        var serial: Int64 = 0
        for e in h.effects { if case .persist(_, _, let s) = e { serial = s } }
        h.apply(h.core.onPersistResult(serial: serial, ok: false))
        XCTAssertEqual(h.snap.retainedConfigPaths, ["/rt/new.json", "/rt/old.json"], "落盘失败：新旧都继续声明")
        h.apply(h.core.onPersistResult(serial: serial, ok: true))
        XCTAssertEqual(h.snap.retainedConfigPaths, ["/rt/new.json"], "确认后旧路径撤下")
    }

    func testUnknownStoredSpecReportsNilRetainedPaths() {
        let core = CoordinatorCore(epoch: "e", storedSpec: nil, storedSpecKnown: false)
        XCTAssertNil(core.snapshot.retainedConfigPaths)
    }

    func testPersistEmittedOnlyWhenIntentChanges() {
        let h = Harness()
        bringUp(h)
        let before = h.count { if case .persist = $0 { return true }; return false }
        _ = h.request(seq: 2, .on, spec: spec(1))
        XCTAssertEqual(h.count { if case .persist = $0 { return true }; return false }, before)
        _ = h.request(seq: 3, .off)
        XCTAssertEqual(h.count { if case .persist = $0 { return true }; return false }, before + 1)
    }

    // MARK: - 版本 / 快照

    func testVersionIsMonotonicAndOnlyBumpsOnChange() {
        let h = Harness()
        h.tunnel(.disconnected)
        let v0 = h.snap.version
        h.tunnel(.disconnected)
        XCTAssertEqual(h.snap.version, v0)
        _ = h.request(seq: 1, .on, spec: spec(1))
        XCTAssertGreaterThan(h.snap.version, v0)
    }

    func testWireMapMatchesDartKeys() {
        let h = Harness()
        let id = bringUp(h)
        _ = id
        let m = h.snap.toWireMap()
        XCTAssertEqual(Set(m.keys), [
            "epoch", "version", "status", "attempt", "desired", "source", "appliedSeq",
            "selectionsReplayNeeded", "activeConfigRevision", "retainedConfigPaths", "lastFailure",
        ])
        XCTAssertEqual(m["status"] as? String, "started")
        XCTAssertEqual(m["desired"] as? String, "on")
        XCTAssertEqual(m["source"] as? String, "app")
        XCTAssertTrue(m["lastFailure"] is NSNull)
    }

    func testEmptyLaunchSpecOnConnectFailsWithEmptyConfiguration() {
        let h = Harness()
        h.tunnel(.disconnected)
        _ = h.request(seq: 1, .on, spec: nil)
        XCTAssertEqual(h.snap.lastFailure?.code, .emptyConfiguration)
        XCTAssertEqual(h.snap.desired, .off)
    }

    // MARK: - 网络

    func testNetworkChangeDoesNotReloadByDefault() {
        let h = Harness()
        bringUp(h)
        h.apply(h.core.onNetworkResolved(10))
        h.apply(h.core.onNetworkResolved(11))
        XCTAssertNil(h.lastReload())
        XCTAssertEqual(h.snap.attempt, 1)
    }

    func testNetworkChangeReloadsAfterDebounceWhenEnabled() {
        let h = Harness(reloadOnNetworkChange: true)
        bringUp(h)
        h.apply(h.core.onNetworkResolved(10)) // 基线
        h.apply(h.core.onNetworkResolved(11))
        var key: TimerKey?
        for e in h.effects { if case .setTimer(let k, _) = e, k.kind == .netDebounce { key = k } }
        h.timer(key!)
        XCTAssertNotNil(h.lastReload())
        XCTAssertEqual(h.snap.attempt, 2)
    }
}
