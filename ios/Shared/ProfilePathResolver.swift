//
//  ProfilePathResolver.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Resolves shared on-disk locations used by both the main application
//  and the packet-tunnel extension. Anything that crosses the process
//  boundary (libcore working state, generated configs, logs) lives
//  under the App Group container.
//

import Foundation

/// Single source of truth for filesystem layout across the app + extension.
///
/// All paths are derived from the App Group container so the two
/// processes see the exact same data. Both Runner.entitlements and
/// SingBoxPacketTunnel.entitlements must declare the group below.
public enum ProfilePathResolver {

    /// Application bundle identifier root (e.g. `com.clashmiao.shared`).
    /// Sourced from `Base.xcconfig` -> `Info.plist` -> here at runtime so
    /// we can avoid hard-coding strings in code.
    public static let bundleRoot: String = {
        Bundle.main.infoDictionary?["BASE_BUNDLE_IDENTIFIER"] as? String
            ?? "com.clashmiao.shared"
    }()

    /// App Group identifier shared between Runner and the extension.
    /// Apple's convention is `group.<id>` – keep the prefix.
    public static let appGroupIdentifier = "group.\(bundleRoot)"

    /// Root of the App Group container.
    ///
    /// Force-unwrap is intentional: if this returns nil at runtime, the
    /// entitlements are misconfigured and we want a crash early during
    /// QA rather than silent data corruption later.
    public static let sharedContainer: URL = {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            fatalError("[ClashMiao] App Group container is unavailable. " +
                       "Did you forget to enable App Groups on both targets?")
        }
        return url
    }()

    /// Library/Caches sub-directory. libcore drops geo databases, cache
    /// files and stderr redirection here.
    public static let cacheDirectory = sharedContainer
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)

    /// Working directory passed to `LibboxSetup`. Holds the active
    /// rule-set cache and the libbox unix-domain command socket.
    public static let runtimeWorkingDirectory = cacheDirectory
        .appendingPathComponent("Runtime", isDirectory: true)

    /// Runner 与扩展交换意图 / 事实的目录。不放 `Library/Caches`（系统可能清理），
    /// 也不放 Dart 的 `Runtime/`（Dart 启动器会清理 `runtime-*.json`）。
    public static let kernelDirectory = sharedContainer
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("ClashMiao", isDirectory: true)
        .appendingPathComponent("kernel", isDirectory: true)

    /// Runner 写、扩展读：当前意图与启动 / 重载产物引用。
    public static let intentFile = kernelDirectory.appendingPathComponent("intent.json")

    /// 扩展写、Runner 读：扩展对自己所处阶段的如实记录。
    public static let extensionStateFile = kernelDirectory.appendingPathComponent("extension-state.json")

    /// 已拼好的最终配置文件路径（按 revision 命名，原生独占；Dart 的清理不会碰它）。
    public static func finalConfig(revision: Int64) -> URL {
        kernelDirectory.appendingPathComponent("final-\(revision).json")
    }
}

public extension URL {
    /// Convenience: just the final path component without a directory prefix.
    /// Used by the log / profile views to display human-readable file names.
    var fileBaseName: String {
        lastPathComponent
    }
}
