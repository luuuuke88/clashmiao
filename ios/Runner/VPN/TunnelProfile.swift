//
//  TunnelProfile.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  开发用配置选项的小封装（见下）。

import Foundation

/// 只留 `configOptions`：`generateFullConfig`（开发用的「看最终配置」）读它。
/// 连接生命周期的一切（spec、desired、final 配置）都在 `KernelStore` / 协调器里，不在这里。
final class TunnelProfile {

    static let shared = TunnelProfile()

    private let store: UserDefaults

    private enum Keys {
        static let configOptions = "ClashMiao.ConfigOptions"
    }

    private init() {
        self.store = UserDefaults(suiteName: ProfilePathResolver.appGroupIdentifier) ?? .standard
    }

    /// JSON blob fed into `MobileBuildConfig`. Updated via `changeConfigOptions` from the Dart side.
    var configOptions: String {
        get { store.string(forKey: Keys.configOptions) ?? "" }
        set { store.set(newValue, forKey: Keys.configOptions) }
    }
}
