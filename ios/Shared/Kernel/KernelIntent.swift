//
//  KernelIntent.swift
//  ClashMiao (Runner + SingBoxPacketTunnel)
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Runner 与扩展之间的落盘契约之一：`intent.json`（Runner 唯一写者，扩展只读）。
//  纯 Foundation，不依赖 UIKit / NetworkExtension，便于单测。
//

import Foundation

/// 协调器追求的目标。raw value 即线上 wire 字符串。
public enum Desired: String, Codable, Equatable {
    case on
    case off
}

/// 启动 / 重载所需的不可变产物（每请求独立）。字段与 Dart `LaunchSpec`、Pigeon `LaunchSpecMsg` 一一对应。
public struct LaunchSpec: Codable, Equatable {
    public let runtimeConfigPath: String
    public let optionsJson: String
    public let profileName: String
    public let configRevision: Int64

    public init(runtimeConfigPath: String, optionsJson: String, profileName: String, configRevision: Int64) {
        self.runtimeConfigPath = runtimeConfigPath
        self.optionsJson = optionsJson
        self.profileName = profileName
        self.configRevision = configRevision
    }
}

/// 失败码。raw value 与 Dart `KernelFailureCode` 逐字一致（原生不发 coreUnavailable）。
public enum FailureCode: String, Codable, Equatable {
    case startTimeout
    case permissionDenied
    case emptyConfiguration
    case createService
    case startService
    case startCommandServer
    case kernelUnresponsive
    case kernelExited
    case unknown
}

/// `intent.json` 的内容。
///
/// - `launchId`：Runner 每次发起启动 / 重载时重新生成；扩展原样写进 `extension-state.json`，
///   Runner 据此区分「这次启动的结果」与「上一次的残留」。
/// - `finalConfigPath`：`ConfigBuilder` 已拼好、落盘的最终配置；扩展只读它，不解析、不拼装。
/// - 扩展**不看** `desired`：隧道被起来就说明系统层面的意图是开（设置里手动打开 VPN、按需连接）。
public struct KernelIntent: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var desired: Desired
    public var launchId: String
    public var spec: LaunchSpec?
    public var finalConfigPath: String?
    /// `finalConfigPath` 对应的 `configRevision`；扩展据此在 state 里如实报告它跑的是哪一版。
    public var finalRevision: Int64?

    public init(
        desired: Desired,
        launchId: String,
        spec: LaunchSpec?,
        finalConfigPath: String?,
        finalRevision: Int64? = nil,
        version: Int = KernelIntent.currentVersion
    ) {
        self.version = version
        self.desired = desired
        self.launchId = launchId
        self.spec = spec
        self.finalConfigPath = finalConfigPath
        self.finalRevision = finalRevision
    }
}

/// 原子读写 JSON 小文件。读取永不抛：文件缺失 / 损坏 / 版本不认识都返回 nil（调用方按「没有」处理）。
public enum KernelFile {
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 原子写（先写临时文件再改名）；返回是否确认写成功。
    @discardableResult
    public static func write<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            #if os(iOS)
            // 锁屏后系统直接启动扩展也要读得到：首次解锁后即可访问。
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path
            )
            #endif
            return true
        } catch {
            return false
        }
    }
}
