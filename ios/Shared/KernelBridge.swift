//
//  KernelBridge.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  内核门面（`Core*`，由仓库内 kernel/ 模块经 gomobile 生成）的薄封装：
//  Runner 与扩展都经这里做进程级 Setup 与无状态调用（解析、构建、WARP）。
//

import Foundation
import Libcore

/// 内核调用失败，统一成 Swift 错误（NSError 的 domain 对调用方没有意义）。
public enum KernelBridgeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case kernelFailed(code: Int, message: String)

    public var description: String {
        switch self {
        case .invalidArguments(let detail):
            return "[ClashMiao] invalid arguments: \(detail)"
        case .kernelFailed(let code, let message):
            return "[ClashMiao] kernel error (\(code)): \(message)"
        }
    }

    /// 内核原文（带稳定前缀，如 `format-unknown:`），给 Flutter 侧做映射用。
    public var message: String {
        switch self {
        case .invalidArguments(let detail): return detail
        case .kernelFailed(_, let message): return message
        }
    }

    init(_ error: NSError) {
        self = .kernelFailed(code: error.code, message: error.localizedDescription)
    }
}

/// 无状态门面：内核自己持有进程级状态，这里不该有实例。
public enum KernelBridge {

    // MARK: - 进程级初始化

    /// 内核命令服务器的 socket 固定在 `<BasePath>/command.sock`。unix socket 的路径（含结尾 NUL）
    /// 不能超过 104 字节；App Group 根目录通常约 90 字节，换了更长的路径要在这里明确失败，而不是连不上。
    public static let commandSocketPathLimit = 104

    /// 命令 socket 的完整路径是否放得下。
    public static func commandSocketPathFits(basePath: String) -> Bool {
        (basePath + "/command.sock").utf8.count + 1 <= commandSocketPathLimit
    }

    /// 进程级 Setup。两个进程用同一个 `basePath`（App Group 根，命令 socket 在这里），
    /// `workingPath` / `tempPath` 各用各的：内核会把 stderr 重定向到 `workingPath` 下的崩溃日志。
    public static func setup(basePath: String,
                             workingPath: String,
                             tempPath: String,
                             memoryLimited: Bool) throws {
        guard commandSocketPathFits(basePath: basePath) else {
            throw KernelBridgeError.invalidArguments("command socket path too long: \(basePath.utf8.count) bytes")
        }
        for dir in [workingPath, tempPath] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let options = CoreSetupOptions()
        options.basePath = basePath
        options.workingPath = workingPath
        options.tempPath = tempPath
        options.logMaxLines = 300
        options.memoryLimited = memoryLimited
        var error: NSError?
        CoreSetup(options, &error)
        if let error { throw KernelBridgeError(error) }
    }

    /// Runner 进程的 Setup：只做客户端（订阅、选择、测速）与无状态调用，幂等。
    private static let runnerSetupLock = NSLock()
    private static var runnerSetupDone = false

    public static func setupRunnerOnce() throws {
        runnerSetupLock.lock()
        defer { runnerSetupLock.unlock() }
        if runnerSetupDone { return }
        try setup(
            basePath: ProfilePathResolver.sharedContainer.path,
            workingPath: ProfilePathResolver.runnerKernelDirectory.path,
            tempPath: ProfilePathResolver.runnerKernelDirectory.appendingPathComponent("tmp", isDirectory: true).path,
            memoryLimited: false
        )
        runnerSetupDone = true
    }

    // MARK: - 无状态调用

    /// 校验并规范化订阅文件：读 `tempPath` 的原文，解析结果写到 `path`。
    /// 成功返回 nil，失败返回内核的错误文本（带稳定前缀，界面按前缀映射文案）。
    public static func parseProfile(at path: String, tempPath: String, debug: Bool) -> String? {
        var error: NSError?
        CoreParse(path, tempPath, debug, &error)
        return error?.localizedDescription
    }

    /// 订阅文件 + configOptions JSON → 运行配置文本。
    public static func buildFullConfig(profilePath: String, options: String) throws -> String {
        var error: NSError?
        let config = CoreBuildConfig(profilePath, options, &error)
        if let error { throw KernelBridgeError(error) }
        return config
    }

    /// 注册一台 WARP 设备；失败抛出（错误以 `warp-` 前缀开头）。
    public static func generateWarpCredential(licenseKey: String,
                                              previousAccountId: String,
                                              previousAccessToken: String) throws -> String {
        var error: NSError?
        let json = CoreGenerateWarpConfig(licenseKey, previousAccountId, previousAccessToken, &error)
        if let error { throw KernelBridgeError(error) }
        return json
    }
}
