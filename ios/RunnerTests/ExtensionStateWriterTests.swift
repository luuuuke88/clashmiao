import XCTest
@testable import Runner

final class ExtensionStateWriterTests: XCTestCase {

    private func makeWriter() -> (ExtensionStateWriter, URL) {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("esw-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("state.json")
        return (ExtensionStateWriter(url: url, sessionId: "S", launchId: "L1"), url)
    }

    func testStartsAsStartingAndPersistsImmediately() {
        let (_, url) = makeWriter()
        let st = KernelFile.read(ExtensionState.self, from: url)
        XCTAssertEqual(st?.phase, .starting)
        XCTAssertEqual(st?.sessionId, "S")
        XCTAssertEqual(st?.generation, 0)
    }

    func testRunningBumpsGenerationEachTime() {
        let (w, url) = makeWriter()
        XCTAssertTrue(w.markRunning(launchId: "L1", revision: 7))
        XCTAssertEqual(KernelFile.read(ExtensionState.self, from: url)?.generation, 1)
        XCTAssertTrue(w.markReloading(launchId: "L2"))
        XCTAssertEqual(KernelFile.read(ExtensionState.self, from: url)?.generation, 1, "重载进行中 generation 不变")
        XCTAssertTrue(w.markRunning(launchId: "L2", revision: 8))
        let st = KernelFile.read(ExtensionState.self, from: url)
        XCTAssertEqual(st?.generation, 2)
        XCTAssertEqual(st?.revision, 8)
        XCTAssertEqual(st?.launchId, "L2")
    }

    func testFailedIsTerminalAndNotOverwrittenByStopped() {
        let (w, url) = makeWriter()
        w.markRunning(launchId: "L1", revision: 1)
        XCTAssertTrue(w.markFailed(code: .createService, message: "boom"))
        XCTAssertFalse(w.markStopped(reason: 1), "失败记录不能被后面的 stopped 覆盖")
        XCTAssertFalse(w.markRunning(launchId: "L1", revision: 1), "终态之后迟到的 running 被丢弃")
        XCTAssertFalse(w.noteAvailableMemory(1))
        let st = KernelFile.read(ExtensionState.self, from: url)
        XCTAssertEqual(st?.phase, .failed)
        XCTAssertEqual(st?.code, .createService)
        XCTAssertNil(st?.stopReason)
    }

    func testStoppedIsTerminal() {
        let (w, _) = makeWriter()
        w.markRunning(launchId: "L1", revision: 1)
        XCTAssertTrue(w.markStopped(reason: 1))
        XCTAssertTrue(w.isTerminal)
        XCTAssertFalse(w.markFailed(code: .unknown, message: "late"))
    }

    func testMemoryOnlyRecordsNewLows() {
        let (w, url) = makeWriter()
        XCTAssertTrue(w.noteAvailableMemory(30_000_000))
        XCTAssertFalse(w.noteAvailableMemory(40_000_000), "更高的余量不写盘")
        XCTAssertTrue(w.noteAvailableMemory(20_000_000))
        XCTAssertEqual(KernelFile.read(ExtensionState.self, from: url)?.availableMemoryMin, 20_000_000)
    }
}
