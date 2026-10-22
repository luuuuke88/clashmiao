import XCTest
@testable import Runner

final class ConfigBuilderTests: XCTestCase {

    // MARK: - tun inbound 去重（与 Android TunInboundsTest 同口径）

    private func inboundTypes(_ content: String) -> [String] {
        let obj = try! JSONSerialization.jsonObject(with: Data(content.utf8)) as! [String: Any]
        return (obj["inbounds"] as! [[String: Any]]).map { $0["type"] as! String }
    }

    func testSingleTunInboundIsLeftUntouched() {
        let content = #"{"inbounds":[{"type":"mixed"},{"type":"tun","tag":"a"}]}"#
        let r = TunInbounds.keepLast(content)
        XCTAssertEqual(r.removed, 0)
        XCTAssertEqual(r.content, content, "没有要删的就原样返回，不重新序列化")
    }

    func testNoInboundsIsLeftUntouched() {
        let content = #"{"outbounds":[]}"#
        XCTAssertEqual(TunInbounds.keepLast(content), TunInbounds.Result(content: content, removed: 0))
    }

    func testMultipleTunInboundsKeepOnlyTheLast() {
        let content = #"{"inbounds":[{"type":"tun","tag":"sub"},{"type":"mixed"},{"type":"tun","tag":"opts"}]}"#
        let r = TunInbounds.keepLast(content)
        XCTAssertEqual(r.removed, 1)
        XCTAssertEqual(inboundTypes(r.content), ["mixed", "tun"])
        let obj = try! JSONSerialization.jsonObject(with: Data(r.content.utf8)) as! [String: Any]
        let tags = (obj["inbounds"] as! [[String: Any]]).compactMap { $0["tag"] as? String }
        XCTAssertEqual(tags, ["opts"], "留下的是内核按当前设置 append 的最后一个")
    }

    func testUnparseableTextIsReturnedAsIs() {
        let r = TunInbounds.keepLast("not json")
        XCTAssertEqual(r, TunInbounds.Result(content: "not json", removed: 0))
    }

    func testOtherTopLevelFieldsSurviveDedupe() {
        let content = #"{"log":{"level":"info"},"inbounds":[{"type":"tun"},{"type":"tun"}],"outbounds":[{"type":"direct"}]}"#
        let r = TunInbounds.keepLast(content)
        let obj = try! JSONSerialization.jsonObject(with: Data(r.content.utf8)) as! [String: Any]
        XCTAssertNotNil(obj["log"])
        XCTAssertEqual((obj["outbounds"] as! [Any]).count, 1)
    }

    // MARK: - ConfigBuilder

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("cb-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    private func spec(_ rev: Int64) -> LaunchSpec {
        LaunchSpec(runtimeConfigPath: "/rt/runtime-\(rev).json", optionsJson: "{\"a\":1}", profileName: "p", configRevision: rev)
    }

    func testBuildWritesImmutableFinalFileNamedByRevision() throws {
        let dir = tempDir()
        var seen: (String, String)?
        let b = ConfigBuilder(assemble: { p, o in seen = (p, o); return #"{"inbounds":[{"type":"tun"},{"type":"tun"}]}"# }, directory: dir)
        let built = try b.build(spec: spec(42))
        XCTAssertEqual(seen?.0, "/rt/runtime-42.json")
        XCTAssertEqual(seen?.1, "{\"a\":1}")
        XCTAssertEqual(built.revision, 42)
        XCTAssertEqual(built.path, dir.appendingPathComponent("final-42.json").path)
        let text = try String(contentsOfFile: built.path, encoding: .utf8)
        XCTAssertEqual(inboundTypes(text), ["tun"], "落盘的是去重后的内容")
    }

    func testBuildRejectsEmptyInputsAndWrapsAssembleErrors() {
        let dir = tempDir()
        struct Boom: Error {}
        let b = ConfigBuilder(assemble: { _, _ in throw Boom() }, directory: dir)
        XCTAssertThrowsError(try b.build(spec: LaunchSpec(runtimeConfigPath: "", optionsJson: "{}", profileName: "", configRevision: 1))) {
            XCTAssertEqual(($0 as? ConfigBuildError), .emptyInput("empty runtime config path"))
        }
        XCTAssertThrowsError(try b.build(spec: LaunchSpec(runtimeConfigPath: "/x", optionsJson: "", profileName: "", configRevision: 1))) {
            guard case .emptyInput = ($0 as? ConfigBuildError) else { return XCTFail("expected emptyInput") }
        }
        XCTAssertThrowsError(try b.build(spec: spec(1))) {
            guard case .assembleFailed = ($0 as? ConfigBuildError) else { return XCTFail("expected assembleFailed") }
        }
    }

    func testPruneKeepsOnlyListedRevisionsAndIgnoresOtherFiles() throws {
        let dir = tempDir()
        let b = ConfigBuilder(assemble: { _, _ in "{}" }, directory: dir)
        for rev: Int64 in [1, 2, 3] { _ = try b.build(spec: spec(rev)) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("intent.json"))
        try Data("x".utf8).write(to: dir.appendingPathComponent("final-notanumber.json"))
        // 保护期内的一律保留（扩展可能刚读了 intent、还没打开它引用的 final）。
        b.prune(keepRevisions: [3, 2])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)),
                       ["final-1.json", "final-2.json", "final-3.json", "intent.json", "final-notanumber.json"])
        // 把 rev 1 的修改时间调到保护期之外：这时才会被清理。
        let old = Date().addingTimeInterval(-(ConfigBuilder.pruneGrace + 10))
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.appendingPathComponent("final-1.json").path)
        b.prune(keepRevisions: [3, 2])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)),
                       ["final-2.json", "final-3.json", "intent.json", "final-notanumber.json"])
    }

    /// iOS 用的是 1.8.9 内核，而 Dart 选项的跨语言契约（`kernel/testdata/options`）只对 Android 的新内核验证过。
    /// 这里把同一批 Dart 产出的选项逐个交给 iOS 内核组装完整配置：任何一份组装失败、或缺了 dns / route /
    /// inbounds，iOS 上点连接就会失败。WARP 在 iOS 不提供，跳过。
    func testIOSKernelAssemblesEveryDartOptionsFixture() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let testdata = repo.appendingPathComponent("kernel/testdata")
        // 订阅形态取共享夹具里的普通出站（iOS 内核不认 endpoints）。
        let mixed = try JSONSerialization.jsonObject(
            with: Data(contentsOf: testdata.appendingPathComponent("shared/profiles/mixed.json"))) as! [String: Any]
        let profile: [String: Any] = ["outbounds": (mixed["outbounds"] as! [Any]) + [["type": "direct", "tag": "direct"]]]
        let profileURL = tempDir().appendingPathComponent("profile.json")
        try JSONSerialization.data(withJSONObject: profile).write(to: profileURL)

        let optionsDir = testdata.appendingPathComponent("options")
        let names = try FileManager.default.contentsOfDirectory(atPath: optionsDir.path)
            .filter { $0.hasSuffix(".json") && !$0.contains("warp") }
            .sorted()
        XCTAssertGreaterThan(names.count, 20)
        for name in names {
            let options = try String(contentsOf: optionsDir.appendingPathComponent(name), encoding: .utf8)
            do {
                let full = try KernelBridge.buildFullConfig(profilePath: profileURL.path, options: options)
                let root = try JSONSerialization.jsonObject(with: Data(full.utf8)) as? [String: Any]
                for key in ["dns", "route", "inbounds", "outbounds"] {
                    XCTAssertNotNil(root?[key], "\(name): 完整配置缺 \(key)")
                }
            } catch {
                XCTFail("\(name): iOS 内核组装失败：\(error)")
            }
        }
    }
}
