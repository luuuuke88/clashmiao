import XCTest
@testable import Runner

/// Runner 与扩展之间的落盘 / 消息契约。
final class KernelContractTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("kc-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    private let spec = LaunchSpec(runtimeConfigPath: "/rt/runtime-7.json", optionsJson: "{}", profileName: "p", configRevision: 7)

    func testIntentRoundTripKeepsInt64Revision() {
        let url = tempDir().appendingPathComponent("intent.json")
        let big: Int64 = 9_007_199_254_740_993 // 超过 2^53：不能经 Double
        let intent = KernelIntent(
            desired: .on, launchId: "L", spec: LaunchSpec(runtimeConfigPath: "/a", optionsJson: "{}", profileName: "p", configRevision: big),
            finalConfigPath: "/f", finalRevision: big
        )
        XCTAssertTrue(KernelFile.write(intent, to: url))
        XCTAssertEqual(KernelFile.read(KernelIntent.self, from: url), intent)
    }

    func testReadingMissingOrCorruptFileReturnsNil() throws {
        let dir = tempDir()
        XCTAssertNil(KernelFile.read(KernelIntent.self, from: dir.appendingPathComponent("none.json")))
        let bad = dir.appendingPathComponent("bad.json")
        try Data("{ not json".utf8).write(to: bad)
        XCTAssertNil(KernelFile.read(ExtensionState.self, from: bad))
    }

    func testUnknownPhaseMakesTheWholeStateUnreadable() throws {
        let url = tempDir().appendingPathComponent("s.json")
        try Data(#"{"sessionId":"s","launchId":"l","phase":"weird","generation":1,"updatedAt":0}"#.utf8).write(to: url)
        XCTAssertNil(KernelFile.read(ExtensionState.self, from: url), "不认识的 phase 不能被当成某个已知阶段")
    }

    func testExtensionStateRoundTrip() {
        let url = tempDir().appendingPathComponent("s.json")
        let st = ExtensionState(sessionId: "S", launchId: "L", phase: .failed, generation: 3, revision: 7,
                                code: .createService, message: "m", stopReason: nil, availableMemoryMin: 1234)
        XCTAssertTrue(KernelFile.write(st, to: url))
        let back = KernelFile.read(ExtensionState.self, from: url)
        XCTAssertEqual(back?.code, .createService)
        XCTAssertEqual(back?.generation, 3)
        XCTAssertEqual(back?.availableMemoryMin, 1234)
    }

    func testFailureCodeWireStringsMatchDart() {
        XCTAssertEqual(
            Set(["startTimeout", "permissionDenied", "emptyConfiguration", "createService", "startService",
                 "startCommandServer", "kernelUnresponsive", "kernelExited", "unknown"]),
            Set([FailureCode.startTimeout, .permissionDenied, .emptyConfiguration, .createService, .startService,
                 .startCommandServer, .kernelUnresponsive, .kernelExited, .unknown].map(\.rawValue))
        )
    }

    func testStopReasonClassification() {
        for r in [2, 7, 14] { XCTAssertTrue(StopReasonClass.isFailure(r)) }
        for r in [0, 1, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 999] { XCTAssertFalse(StopReasonClass.isFailure(r)) }
        XCTAssertFalse(StopReasonClass.isFailure(nil))
    }

    func testMessageCodecsRoundTrip() throws {
        let req = ExtensionRequest(op: .select, group: "g", outbound: "o", sessionId: "S", generation: 4)
        let back = try JSONDecoder().decode(ExtensionRequest.self, from: JSONEncoder().encode(req))
        XCTAssertEqual(back, req)
        let stale = ExtensionReply(ok: false, code: ExtensionReply.staleCode, message: "m")
        XCTAssertTrue(stale.isStale)
        XCTAssertNil(stale.failureCode)
        XCTAssertEqual(ExtensionReply(ok: false, code: "createService").failureCode, .createService)
    }

    // MARK: - KernelStore

    func testStoreMissingFileIsKnownEmpty() {
        let d = tempDir()
        let s = KernelStore(intentURL: d.appendingPathComponent("intent.json"), stateURL: d.appendingPathComponent("state.json"))
        XCTAssertNil(s.loadedSpec)
        XCTAssertTrue(s.loadedKnown)
    }

    func testStoreCorruptFileIsUnknown() throws {
        let d = tempDir()
        let url = d.appendingPathComponent("intent.json")
        try Data("garbage".utf8).write(to: url)
        let s = KernelStore(intentURL: url, stateURL: d.appendingPathComponent("state.json"))
        XCTAssertNil(s.loadedSpec)
        XCTAssertFalse(s.loadedKnown, "读不出来 = 不知道引用了什么，retainedConfigPaths 必须报未知")
    }

    func testStoreUnknownVersionIsUnknown() throws {
        let d = tempDir()
        let url = d.appendingPathComponent("intent.json")
        var intent = KernelIntent(desired: .on, launchId: "L", spec: spec, finalConfigPath: nil)
        intent.version = 99
        XCTAssertTrue(KernelFile.write(intent, to: url))
        let s = KernelStore(intentURL: url, stateURL: d.appendingPathComponent("state.json"))
        XCTAssertFalse(s.loadedKnown)
    }

    func testCommitIntentThenLaunchPersistAndSurviveReload() {
        let d = tempDir()
        let intentURL = d.appendingPathComponent("intent.json")
        let stateURL = d.appendingPathComponent("state.json")
        let s = KernelStore(intentURL: intentURL, stateURL: stateURL)
        XCTAssertTrue(s.commitIntent(desired: .on, spec: spec))
        XCTAssertTrue(s.commitLaunch(launchId: "L1", spec: spec, built: BuiltConfig(path: "/f/final-7.json", revision: 7)))
        XCTAssertTrue(s.commitIntent(desired: .off, spec: nil))
        let back = KernelStore(intentURL: intentURL, stateURL: stateURL)
        XCTAssertEqual(back.loadedSpec, spec)
        XCTAssertEqual(back.current.desired, .off, "commitLaunch 不改 desired，之后的 off 被如实保存")
        XCTAssertEqual(back.current.finalConfigPath, "/f/final-7.json", "off 不丢掉 final 引用（系统直接启动仍可用）")
        XCTAssertEqual(back.current.launchId, "L1")
    }

    func testStoreReadsExtensionState() {
        let d = tempDir()
        let stateURL = d.appendingPathComponent("state.json")
        let s = KernelStore(intentURL: d.appendingPathComponent("intent.json"), stateURL: stateURL)
        XCTAssertNil(s.readExtensionState())
        KernelFile.write(ExtensionState(sessionId: "S", launchId: "L", phase: .running, generation: 1, revision: 7), to: stateURL)
        XCTAssertEqual(s.readExtensionState()?.revision, 7)
    }
}
