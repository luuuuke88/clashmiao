//
//  ConfigBuilder.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  把 LaunchSpec 拼成最终运行配置并落盘（iOS 设计 §5）。
//
//  拼配置放在 Runner 而不是扩展：扩展约 50 MB 的硬上限容不下「解析一遍整份订阅 + 再序列化」的瞬时峰值，
//  所以扩展只读这里写好的 `final-<revision>.json`，原样交给内核。
//
//  纯 Foundation：真正调用内核拼装的函数从外部注入（见 `TunnelController` 的接线），便于单测。
//

import Foundation

/// 最终运行配置里的 tun inbound 只能有一个。
///
/// tun 只该由启动参数 `enable-tun` 交给内核配置构建器创建（它把自己的 tun inbound append 在订阅
/// inbounds 之后）。订阅自带 tun 时会出现两个：两套 tun 协议栈抢同一个地址，偶发 tun 转发监听缺失、
/// 经 tun 的 TCP 全被拒，界面却显示已连接（Android 真机验收 BUG-B 同源）。这里在交给内核之前收口：
/// 多于一个时只留最后一个（内核按当前网络设置 append 的那个）。解析不了的文本原样返回，让内核自己报配置错误。
enum TunInbounds {
    struct Result: Equatable {
        let content: String
        let removed: Int
    }

    static func keepLast(_ content: String) -> Result {
        guard
            let data = content.data(using: .utf8),
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let inbounds = root["inbounds"] as? [Any]
        else {
            return Result(content: content, removed: 0)
        }
        let tunIndexes = inbounds.indices.filter { (inbounds[$0] as? [String: Any])?["type"] as? String == "tun" }
        if tunIndexes.count <= 1 { return Result(content: content, removed: 0) }
        let drop = Set(tunIndexes.dropLast())
        root["inbounds"] = inbounds.enumerated().filter { !drop.contains($0.offset) }.map { $0.element }
        guard let out = try? JSONSerialization.data(withJSONObject: root),
              let text = String(data: out, encoding: .utf8)
        else {
            return Result(content: content, removed: 0)
        }
        return Result(content: text, removed: drop.count)
    }
}

enum ConfigBuildError: Error, Equatable {
    case emptyInput(String)
    case assembleFailed(String)
    case writeFailed(String)

    var message: String {
        switch self {
        case .emptyInput(let m), .assembleFailed(let m), .writeFailed(let m): return m
        }
    }
}

/// 已落盘的最终配置。
struct BuiltConfig: Equatable {
    let path: String
    let revision: Int64
}

protocol ConfigBuilding {
    /// 拼装并原子落盘；阻塞，只能在执行层调用。
    func build(spec: LaunchSpec) throws -> BuiltConfig
    /// 删除不在 `keep` 里、且修改时间早于保护期的 `final-*.json`。保护期内的一律保留：
    /// 扩展可能刚读了 intent、还没打开它引用的 final（iOS 设计 §3）。
    func prune(keepRevisions: Set<Int64>)
}

struct ConfigBuilder: ConfigBuilding {
    /// `(profile 路径, options JSON) → 最终配置文本`；生产实现是内核的 `MobileBuildConfig`。
    let assemble: (_ profilePath: String, _ optionsJson: String) throws -> String
    let directory: URL
    var log: (String) -> Void = { _ in }

    func finalURL(revision: Int64) -> URL {
        directory.appendingPathComponent("final-\(revision).json")
    }

    func build(spec: LaunchSpec) throws -> BuiltConfig {
        if spec.runtimeConfigPath.isEmpty { throw ConfigBuildError.emptyInput("empty runtime config path") }
        if spec.optionsJson.isEmpty { throw ConfigBuildError.emptyInput("empty config options") }
        let raw: String
        do {
            raw = try assemble(spec.runtimeConfigPath, spec.optionsJson)
        } catch {
            throw ConfigBuildError.assembleFailed(error.localizedDescription)
        }
        let result = TunInbounds.keepLast(raw)
        if result.removed > 0 {
            log("dropped \(result.removed) duplicate tun inbound(s) from \(spec.runtimeConfigPath)")
        }
        let url = finalURL(revision: spec.configRevision)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(result.content.utf8).write(to: url, options: .atomic)
        } catch {
            throw ConfigBuildError.writeFailed(error.localizedDescription)
        }
        return BuiltConfig(path: url.path, revision: spec.configRevision)
    }

    /// 刚写好的 final 在这段时间内不会被清理。
    static let pruneGrace: TimeInterval = 120

    func prune(keepRevisions: Set<Int64>) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Self.pruneGrace)
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix("final-") && name.hasSuffix(".json") {
            let digits = name.dropFirst("final-".count).dropLast(".json".count)
            guard let rev = Int64(digits), !keepRevisions.contains(rev) else { continue }
            let url = directory.appendingPathComponent(name)
            let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
            if let modified, modified > cutoff { continue }
            try? fm.removeItem(at: url)
        }
    }
}
