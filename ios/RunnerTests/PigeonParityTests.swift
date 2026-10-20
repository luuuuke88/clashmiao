import XCTest
@testable import Runner

/// Pigeon 查询（`KernelSnapshotMsg`）与事件通道（JSON map）必须来自同一份字段、同值（Dart 的版本过滤依赖这一点）。
/// 依赖 Flutter 生成的 `BoxApi.g.swift`，只在 Xcode 测试 target 里编译。
final class PigeonParityTests: XCTestCase {

    private func sample(failure: Bool) -> KernelSnapshot {
        KernelSnapshot(
            epoch: "e", version: 9, status: .starting, attempt: 3, desired: .on, source: .system,
            appliedSeq: 4, activeConfigRevision: 9_007_199_254_740_993,
            lastFailure: failure ? KernelFailure(code: .startTimeout, message: "m", attempt: 2, seq: 4) : nil,
            selectionsReplayNeeded: true, retainedConfigPaths: ["/a", "/b"]
        )
    }

    func testMsgAndWireMapCarrySameValues() {
        for failure in [false, true] {
            let s = sample(failure: failure)
            let msg = s.toMsg()
            let map = s.toWireMap()
            XCTAssertEqual(map["epoch"] as? String, msg.epoch)
            XCTAssertEqual(map["version"] as? Int64, msg.version)
            XCTAssertEqual(map["status"] as? String, msg.status)
            XCTAssertEqual(map["attempt"] as? Int64, msg.attempt)
            XCTAssertEqual(map["desired"] as? String, msg.desired)
            XCTAssertEqual(map["source"] as? String, msg.source)
            XCTAssertEqual(map["appliedSeq"] as? Int64, msg.appliedSeq)
            XCTAssertEqual(map["activeConfigRevision"] as? Int64, msg.activeConfigRevision, "63 位 revision 不能经 Double 丢精度")
            XCTAssertEqual(map["selectionsReplayNeeded"] as? Bool, msg.selectionsReplayNeeded)
            XCTAssertEqual(map["retainedConfigPaths"] as? [String], msg.retainedConfigPaths)
            if failure {
                let f = map["lastFailure"] as? [String: Any]
                XCTAssertEqual(f?["code"] as? String, msg.lastFailure?.code)
                XCTAssertEqual(f?["attempt"] as? Int64, msg.lastFailure?.attempt)
                XCTAssertEqual(f?["seq"] as? Int64, msg.lastFailure?.seq)
            } else {
                XCTAssertNil(msg.lastFailure)
                XCTAssertTrue(map["lastFailure"] is NSNull)
            }
        }
    }

    func testUnknownRetainedPathsStayNilNotEmpty() {
        var s = sample(failure: false)
        s.retainedConfigPaths = nil
        XCTAssertNil(s.toMsg().retainedConfigPaths)
        XCTAssertTrue(s.toWireMap()["retainedConfigPaths"] is NSNull, "null = 未知，[] = 确知没有引用，二者不能混")
    }

    func testStatusLabelsOfCompatStream() {
        XCTAssertEqual(TunnelStatusStream.label(.started), "Started")
        XCTAssertEqual(TunnelStatusStream.label(.starting), "Starting")
        XCTAssertEqual(TunnelStatusStream.label(.stopping), "Stopping")
        XCTAssertEqual(TunnelStatusStream.label(.stopped), "Stopped")
    }
}
