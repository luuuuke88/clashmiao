import XCTest
@testable import Runner

/// `KernelCoordinator` 外壳：假隧道适配器 + 假拼装器 + 手动定时器，真实的队列。
final class KernelCoordinatorTests: XCTestCase {

    // MARK: - 替身

    final class FakeAdapter: TunnelAdapter {
        private let lock = NSLock()
        private var _status: TunnelStatus = .disconnected
        private var handlers: [(TunnelStatus) -> Void] = []
        var configureError: TunnelAdapterError?
        var startError: TunnelAdapterError?
        /// 提交 start 后是否让状态可见地变成 connecting（false = 模拟系统没接这次提交）。
        var startMakesTunnelVisible = true
        private var _startCalls = 0
        private var _stopCalls = 0
        private var _messages: [ExtensionRequest] = []
        var startCalls: Int { lock.lock(); defer { lock.unlock() }; return _startCalls }
        var stopCalls: Int { lock.lock(); defer { lock.unlock() }; return _stopCalls }
        var messages: [ExtensionRequest] { lock.lock(); defer { lock.unlock() }; return _messages }
        var reply: (ExtensionRequest) throws -> ExtensionReply = { _ in ExtensionReply(ok: true) }

        var currentStatus: TunnelStatus {
            lock.lock(); defer { lock.unlock() }
            return _status
        }
        func set(_ s: TunnelStatus) {
            lock.lock(); _status = s; let hs = handlers; lock.unlock()
            hs.forEach { $0(s) }
        }
        /// 改状态但不通知：模拟 Runner 被挂起期间错过的事件。
        func setSilently(_ s: TunnelStatus) {
            lock.lock(); _status = s; lock.unlock()
        }
        func observeStatus(_ handler: @escaping (TunnelStatus) -> Void) {
            lock.lock(); handlers.append(handler); lock.unlock()
        }
        func ensureConfigured() throws { if let e = configureError { throw e } }
        func startTunnel() throws {
            lock.lock(); _startCalls += 1; lock.unlock()
            if let e = startError { throw e }
            if startMakesTunnelVisible { set(.connecting) }
        }
        func stopTunnel() { lock.lock(); _stopCalls += 1; lock.unlock() }
        func sendMessage(_ request: ExtensionRequest, timeout: TimeInterval) throws -> ExtensionReply {
            lock.lock(); _messages.append(request); lock.unlock()
            return try reply(request)
        }
    }

    final class FakeBuilder: ConfigBuilding {
        var error: ConfigBuildError?
        private let lock = NSLock()
        private var _built: [Int64] = []
        private var _pruned: [Set<Int64>] = []
        var built: [Int64] { lock.lock(); defer { lock.unlock() }; return _built }
        var pruned: [Set<Int64>] { lock.lock(); defer { lock.unlock() }; return _pruned }
        func build(spec: LaunchSpec) throws -> BuiltConfig {
            if let error { throw error }
            lock.lock(); _built.append(spec.configRevision); lock.unlock()
            return BuiltConfig(path: "/final/final-\(spec.configRevision).json", revision: spec.configRevision)
        }
        func prune(keepRevisions: Set<Int64>) { lock.lock(); _pruned.append(keepRevisions); lock.unlock() }
    }

    final class ManualScheduler: CoordinatorScheduler {
        let queue: DispatchQueue
        private(set) var pending: [String: () -> Void] = [:]
        init(queue: DispatchQueue) { self.queue = queue }
        func schedule(slot: String, delayMs: Int64, _ fire: @escaping () -> Void) { pending[slot] = fire }
        func cancel(slot: String) { pending[slot] = nil }
        func slots(prefix: String) -> [String] { queue.sync { pending.keys.filter { $0.hasPrefix(prefix) } } }
        func fire(prefix: String) {
            queue.sync {
                guard let key = pending.keys.first(where: { $0.hasPrefix(prefix) }) else { return }
                let f = pending.removeValue(forKey: key)
                f?()
            }
        }
    }

    struct Rig {
        let coordinator: KernelCoordinator
        let adapter: FakeAdapter
        let builder: FakeBuilder
        let scheduler: ManualScheduler
        let store: KernelStore
        let stateURL: URL
    }

    private func makeRig(preexistingState: ExtensionState? = nil) -> Rig {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kcoord-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let stateURL = dir.appendingPathComponent("state.json")
        if let st = preexistingState { KernelFile.write(st, to: stateURL) }
        let store = KernelStore(intentURL: dir.appendingPathComponent("intent.json"), stateURL: stateURL)
        let adapter = FakeAdapter()
        let builder = FakeBuilder()
        let queue = DispatchQueue(label: "test.command")
        let scheduler = ManualScheduler(queue: queue)
        let c = KernelCoordinator(
            adapter: adapter, store: store, builder: builder,
            scheduler: { _ in scheduler }, epoch: "epoch-1", tunnelVisibleTimeout: 0.3, queue: queue, log: { _ in }
        )
        return Rig(coordinator: c, adapter: adapter, builder: builder, scheduler: scheduler, store: store, stateURL: stateURL)
    }

    private func spec(_ rev: Int64) -> LaunchSpec {
        LaunchSpec(runtimeConfigPath: "/rt/runtime-\(rev).json", optionsJson: "{}", profileName: "p", configRevision: rev)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 3, _ cond: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() {
            if Date() > deadline { return XCTFail("timeout waiting for \(what)") }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// 让隧道在系统层面起来：写扩展 state、改状态并通知。
    private func bringTunnelUp(_ r: Rig, rev: Int64, session: String = "S1", gen: Int = 1) {
        let launchId = r.store.current.launchId
        KernelFile.write(
            ExtensionState(sessionId: session, launchId: launchId, phase: .running, generation: gen, revision: rev),
            to: r.stateURL
        )
        r.adapter.set(.connected)
    }

    // MARK: - 用例

    func testConnectSucceedsOnceTunnelAndStateAgree() {
        let r = makeRig()
        let receipt = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(5), reason: "t")
        XCTAssertTrue(receipt.accepted)
        waitFor("start submitted") { r.adapter.startCalls == 1 }
        XCTAssertEqual(r.store.current.finalRevision, 5, "先发布最终配置再提交启动")
        XCTAssertEqual(r.coordinator.snapshot.status, .starting)
        waitFor("tunnel visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 5)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        XCTAssertEqual(r.coordinator.snapshot.activeConfigRevision, 5)
        XCTAssertNil(r.coordinator.snapshot.lastFailure)
    }

    func testPermissionDeniedBecomesFailureAndNeverStartsTunnel() {
        let r = makeRig()
        r.adapter.configureError = .permissionDenied("user declined")
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("failure") { r.coordinator.snapshot.lastFailure != nil }
        let snap = r.coordinator.snapshot
        XCTAssertEqual(snap.lastFailure?.code, .permissionDenied)
        XCTAssertEqual(snap.lastFailure?.seq, 1)
        XCTAssertEqual(snap.desired, .off)
        XCTAssertEqual(r.adapter.startCalls, 0)
    }

    func testBuildFailureMapsToEmptyConfiguration() {
        let r = makeRig()
        r.builder.error = .assembleFailed("bad profile")
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("failure") { r.coordinator.snapshot.lastFailure != nil }
        XCTAssertEqual(r.coordinator.snapshot.lastFailure?.code, .emptyConfiguration)
        XCTAssertEqual(r.adapter.startCalls, 0)
    }

    func testTunnelNeverBecomingVisibleFailsInsteadOfHanging() {
        let r = makeRig()
        r.adapter.startMakesTunnelVisible = false
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("failure") { r.coordinator.snapshot.lastFailure != nil }
        XCTAssertEqual(r.coordinator.snapshot.lastFailure?.code, .startService)
        XCTAssertEqual(r.coordinator.snapshot.desired, .off)
        XCTAssertGreaterThanOrEqual(r.adapter.stopCalls, 1, "放弃的启动要补发 stop，撤销可能迟到的启动")
    }

    func testOffStopsTunnelAndReportsStoppedOnlyAfterDisconnected() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 1)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        _ = r.coordinator.request(epoch: "epoch-1", seq: 2, desired: .off, launch: nil)
        waitFor("stop submitted") { r.adapter.stopCalls == 1 }
        XCTAssertEqual(r.coordinator.snapshot.status, .stopping)
        KernelFile.write(ExtensionState(sessionId: "S1", launchId: r.store.current.launchId, phase: .stopped, stopReason: 1), to: r.stateURL)
        r.adapter.set(.disconnected)
        waitFor("stopped") { r.coordinator.snapshot.status == .stopped }
        XCTAssertNil(r.coordinator.snapshot.lastFailure)
    }

    func testTimerReadsFactsFirstSoABackgroundSuccessIsNotKilled() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        waitFor("start timeout armed") { !r.scheduler.slots(prefix: "startTimeout").isEmpty }
        // Runner 被挂起期间隧道已经成功，但我们没收到任何通知。
        KernelFile.write(
            ExtensionState(sessionId: "S1", launchId: r.store.current.launchId, phase: .running, generation: 1, revision: 1),
            to: r.stateURL
        )
        r.adapter.setSilently(.connected)
        r.scheduler.fire(prefix: "startTimeout")
        waitFor("started") { r.coordinator.snapshot.status == .started }
        XCTAssertNil(r.coordinator.snapshot.lastFailure, "恢复后过期的超时不能误杀已成功的启动")
    }

    func testSelectWithWrongAttemptIsStaleAndNeverReachesExtension() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 1)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        let exp = expectation(description: "select")
        var got: SelectResult?
        r.coordinator.selectOutbound(group: "g", outbound: "o", expectedAttempt: 99) { got = $0; exp.fulfill() }
        wait(for: [exp], timeout: 3)
        guard case .stale = got else { return XCTFail("expected stale, got \(String(describing: got))") }
        XCTAssertTrue(r.adapter.messages.isEmpty)
    }

    func testSelectCarriesSessionAndGenerationAndMapsExtensionStale() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 1, session: "S9", gen: 3)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        // 1) 扩展确认
        var exp = expectation(description: "ok")
        var got: SelectResult?
        r.coordinator.selectOutbound(group: "g", outbound: "o", expectedAttempt: 1) { got = $0; exp.fulfill() }
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(got, .ok)
        XCTAssertEqual(r.adapter.messages.last?.op, .select)
        XCTAssertEqual(r.adapter.messages.last?.sessionId, "S9")
        XCTAssertEqual(r.adapter.messages.last?.generation, 3)
        // 2) 扩展在最后一刻发现代次已变：stale，且映射给 Dart
        r.adapter.reply = { _ in ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "generation moved") }
        exp = expectation(description: "stale")
        r.coordinator.selectOutbound(group: "g", outbound: "o", expectedAttempt: 1) { got = $0; exp.fulfill() }
        wait(for: [exp], timeout: 3)
        guard case .stale = got else { return XCTFail("expected stale, got \(String(describing: got))") }
    }

    func testWhenReadyWaitsBoundedThenFiresOnMarkReady() {
        let r = makeRig()
        var results: [Bool] = []
        let exp = expectation(description: "timeout false")
        r.coordinator.whenReady(timeout: 0.05) { results.append($0); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(results, [false])
        let exp2 = expectation(description: "ready true")
        r.coordinator.whenReady(timeout: 2) { ok in
            XCTAssertTrue(ok)
            exp2.fulfill()
        }
        r.coordinator.markReady()
        wait(for: [exp2], timeout: 2)
    }

    func testColdAttachFromRunningTunnelOnFirstSync() {
        let st = ExtensionState(sessionId: "S1", launchId: "ext", phase: .running, generation: 2, revision: 8)
        let r = makeRig(preexistingState: st)
        r.adapter.setSilently(.connected)
        r.coordinator.resync()
        waitFor("attached") { r.coordinator.snapshot.status == .started }
        let snap = r.coordinator.snapshot
        XCTAssertEqual(snap.source, .system)
        XCTAssertEqual(snap.activeConfigRevision, 8)
        XCTAssertEqual(r.adapter.stopCalls, 0)
    }

    func testRequestRejectedAsStaleDoesNotChangeSnapshotVersion() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 4, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        let before = r.coordinator.snapshot
        let receipt = r.coordinator.request(epoch: "epoch-1", seq: 4, desired: .off, launch: nil)
        XCTAssertEqual(receipt.reason, .stale)
        XCTAssertEqual(r.coordinator.snapshot.version, before.version)
    }
}

// MARK: - 评审补充用例
extension KernelCoordinatorTests {

    func testPruneKeepsNewPreviousAndExtensionReportedRevisions() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("first prune") { r.builder.pruned.count == 1 }
        XCTAssertEqual(r.builder.pruned[0], [1])
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 1)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        // 第二次发布（重载到 rev 2）：必须保留上一份（rev 1，也是扩展报告的运行中那份）与新的 rev 2。
        // 真实扩展在回复前先写 state（新 revision），回执带实例标识。
        r.adapter.reply = { [stateURL = r.stateURL] req in
            KernelFile.write(
                ExtensionState(sessionId: "S1", launchId: req.launchId ?? "", phase: .running, generation: 2, revision: 2),
                to: stateURL
            )
            return ExtensionReply(ok: true, sessionId: "S1", generation: 2)
        }
        let rec2 = r.coordinator.request(epoch: "epoch-1", seq: 2, desired: .on, launch: spec(2))
        XCTAssertTrue(rec2.accepted, "\(rec2)")
        waitFor("second prune") { r.builder.pruned.count == 2 }
        XCTAssertEqual(r.builder.pruned[1], [1, 2])
    }

    func testSelectTimesOutFromAcceptanceEvenIfExecutionQueueIsBlockedAndNeverWritesLate() {
        let r = makeRig()
        _ = r.coordinator.request(epoch: "epoch-1", seq: 1, desired: .on, launch: spec(1))
        waitFor("visible") { r.adapter.currentStatus == .connecting }
        bringTunnelUp(r, rev: 1)
        waitFor("started") { r.coordinator.snapshot.status == .started }
        // 让执行队列被一个长任务占住：选择在它后面排队。
        let blocked = DispatchSemaphore(value: 0)
        r.coordinator.blockExecutionQueueForTesting { blocked.wait() }
        let exp = expectation(description: "select done")
        var results: [SelectResult] = []
        r.coordinator.selectOutbound(group: "g", outbound: "o", expectedAttempt: nil, timeout: 0.2) {
            results.append($0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 3)
        XCTAssertEqual(results.count, 1)
        guard case .failed = results[0] else { return XCTFail("expected timeout failure, got \(results[0])") }
        blocked.signal() // 放行：排队的写入此时必须被丢弃
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue(r.adapter.messages.isEmpty, "超时之后排队的选择不得迟到写入")
        XCTAssertEqual(results.count, 1, "done 恰好一次")
    }
}
