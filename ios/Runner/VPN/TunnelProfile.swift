//
//  TunnelProfile.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Persists the user's currently-selected tunnel configuration. Backed
//  by `UserDefaults` so values survive process restarts but are not
//  expensive to read on the hot path.
//
//  These fields live on the Runner side only – the extension reads
//  the actual config via the `Config` NSObject options that Runner
//  passes through `startVPNTunnel(options:)`.
//

import Foundation

/// Mutable bag of profile-related settings. Single-tenant for now:
/// ClashMiao only manages one active profile at a time.
final class TunnelProfile {

    static let shared = TunnelProfile()

    private let store: UserDefaults

    private enum Keys {
        static let activeConfigPath = "ClashMiao.ActiveConfigPath"
        static let activeProfileName = "ClashMiao.ActiveProfileName"
        static let configOptions = "ClashMiao.ConfigOptions"
        static let disableMemoryLimit = "ClashMiao.DisableMemoryLimit"
    }

    private init() {
        // Use the suite-scoped defaults so the extension can read the
        // same values if we ever decide to ship them across the IPC
        // boundary via the App Group.
        self.store = UserDefaults(suiteName: ProfilePathResolver.appGroupIdentifier)
            ?? .standard
    }

    /// On-disk path to the active sing-box profile.
    var activeConfigPath: String {
        get { store.string(forKey: Keys.activeConfigPath) ?? "" }
        set { store.set(newValue, forKey: Keys.activeConfigPath) }
    }

    /// Display name for the active profile.
    var activeProfileName: String {
        get { store.string(forKey: Keys.activeProfileName) ?? "" }
        set { store.set(newValue, forKey: Keys.activeProfileName) }
    }

    /// JSON blob fed into `MobileBuildConfig`. Updated via
    /// `change_config_options` from the Dart side.
    var configOptions: String {
        get { store.string(forKey: Keys.configOptions) ?? "" }
        set { store.set(newValue, forKey: Keys.configOptions) }
    }

    /// When true, the extension skips the libcore memory limit (useful
    /// for power-user workloads that hit the 50MB ceiling).
    var disableMemoryLimit: Bool {
        get { store.bool(forKey: Keys.disableMemoryLimit) }
        set { store.set(newValue, forKey: Keys.disableMemoryLimit) }
    }
}
