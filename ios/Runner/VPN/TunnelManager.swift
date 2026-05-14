//
//  TunnelManager.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Owns the user's NETunnelProviderManager preference and exposes a
//  small async API around it. Everything that talks to the OS-level
//  VPN configuration should go through this object so we have one
//  consistent place to enforce ordering (load before save, save
//  before connect, etc.).
//

import Foundation
import Combine
import NetworkExtension

/// Categories of non-fatal alerts that can be surfaced to the Dart
/// side as a Stream<BoxAlert>.
enum TunnelAlertCategory: String {
    case requestVPNPermission
    case requestNotificationPermission
    case emptyConfiguration
    case commandServerStartFailed
    case kernelCreateFailed
    case kernelStartFailed
}

/// One alert event flowing out of TunnelManager.
struct TunnelAlertEvent {
    let category: TunnelAlertCategory?
    let detail: String?
}

/// Singleton (per process) wrapper around NEVPNManager + the
/// extension's NETunnelProviderManager.
final class TunnelManager: ObservableObject {

    static let shared = TunnelManager()

    // MARK: - Published state

    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: TunnelAlertEvent = .init(category: nil, detail: nil)
    @Published private(set) var uploadBytes: Int64 = 0
    @Published private(set) var downloadBytes: Int64 = 0
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published var hasAnyActiveVPN: Bool = false

    // MARK: - Private state

    private var manager = NEVPNManager.shared()
    private var loaded = false
    private var statusObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private var cancelBag = Set<AnyCancellable>()

    /// When the user pressed "connect". Cached in App Group defaults
    /// so we can recover after a process restart mid-session.
    private var sessionStart: Date? {
        get {
            let key = "ClashMiao.SessionStart"
            guard let v = UserDefaults(suiteName: ProfilePathResolver.appGroupIdentifier)?
                .value(forKey: key) as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: v)
        }
        set {
            UserDefaults(suiteName: ProfilePathResolver.appGroupIdentifier)?
                .set(newValue?.timeIntervalSince1970, forKey: "ClashMiao.SessionStart")
        }
    }

    // MARK: - Lifecycle

    private init() {
        // The OS posts `.NEVPNStatusDidChange` whenever the session
        // moves between states. Keep our @Published in sync so UI
        // bindings remain stable.
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] note in
            guard let connection = note.object as? NEVPNConnection else { return }
            DispatchQueue.main.async {
                self?.state = connection.status
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshTrafficCounters()
            self.elapsedSeconds = -(self.sessionStart?.timeIntervalSinceNow ?? 0)
        }
    }

    deinit {
        if let statusObserver {
            NotificationCenter.default.removeObserver(statusObserver)
        }
        pollTimer?.invalidate()
    }

    // MARK: - Setup

    /// Load (or create) the user's NETunnelProviderManager preference.
    /// Triggers the iOS permission sheet on first run.
    func ensureLoaded() async throws {
        // We don't currently early-return on `loaded` – reloading is
        // cheap and lets the user recover from a manually-revoked
        // preference without restarting the app.
        loaded = true
        try await primePreference()
    }

    private func primePreference() async throws {
        let existing = try await NETunnelProviderManager.loadAllFromPreferences()
        if let first = existing.first {
            manager = first
            return
        }
        // No saved preference: build a fresh one. ClashMiao only ever
        // installs a single preference so we don't worry about
        // multiple-profile mode.
        let fresh = NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Bundle.main.clashMiaoBundleRoot + ".SingBoxPacketTunnel"
        proto.serverAddress = "localhost"
        fresh.protocolConfiguration = proto
        fresh.localizedDescription = "ClashMiao"
        try await fresh.saveToPreferences()
        try await fresh.loadFromPreferences()
        manager = fresh
    }

    private func enableManager() async throws {
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    // MARK: - Connect / disconnect

    /// Bring the tunnel up with the given config and (optional) memory
    /// limit override.
    func connect(with finalisedConfig: String,
                 disableMemoryLimit: Bool = false) async throws {
        await applyCounters(upload: 0, download: 0)
        guard state == .disconnected || state == .invalid else { return }
        try await enableManager()
        try manager.connection.startVPNTunnel(options: [
            "Config": finalisedConfig as NSString,
            "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
        ])
        sessionStart = Date()
    }

    /// Disconnect the tunnel if currently connected. No-op otherwise.
    func disconnect() {
        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }

    /// Wipe the saved preference. Useful as an "uninstall" affordance.
    func resetSavedPreference() {
        loaded = false
        if state != .disconnected && state != .invalid {
            disconnect()
        }
        $state
            .filter { $0 == .disconnected || $0 == .invalid }
            .first()
            .sink { [weak self] _ in
                Task { [weak self] in
                    self?.manager = .shared()
                    do {
                        let prefs = try await NETunnelProviderManager.loadAllFromPreferences()
                        for pref in prefs {
                            try await pref.removeFromPreferences()
                        }
                        try await self?.primePreference()
                    } catch {
                        // Surface but don't crash – the user can re-trigger setup.
                        NSLog("[ClashMiao] resetSavedPreference failed: %@",
                              error.localizedDescription)
                    }
                }
            }
            .store(in: &cancelBag)
    }

    // MARK: - Telemetry

    /// True when a tunnel device (utun*/ppp/ipsec/tap) is currently
    /// active in the system's network configuration. Useful as a
    /// fallback signal when our own state is `.invalid`.
    var isSystemReportingActiveVPN: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let scoped = nsDict["__SCOPED__"] as? NSDictionary else { return false }
        for key in scoped.allKeys.compactMap({ $0 as? String }) {
            if key == "tap" || key == "tun" || key == "ppp" || key.hasPrefix("ipsec") {
                return true
            }
            if key.hasPrefix("utun") {
                return true
            }
        }
        return false
    }

    private func refreshTrafficCounters() {
        let active = isSystemReportingActiveVPN
        if hasAnyActiveVPN != active {
            hasAnyActiveVPN = active
        }
        guard state == .connected else { return }
        guard let session = manager.connection as? NETunnelProviderSession else { return }
        do {
            try session.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let text = String(data: response, encoding: .utf8)
                else { return }
                let parts = text.split(separator: ",").map(String.init)
                guard
                    parts.count == 2,
                    let up = Int64(parts[0]),
                    let down = Int64(parts[1])
                else { return }
                Task { [weak self] in
                    await self?.applyCounters(upload: up, download: down)
                }
            }
        } catch {
            // The session can disappear momentarily during reasserts;
            // just skip this tick.
        }
    }

    @MainActor
    private func applyCounters(upload: Int64, download: Int64) {
        uploadBytes = upload
        downloadBytes = download
    }
}
