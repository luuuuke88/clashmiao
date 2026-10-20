//
//  TunnelController.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  `TunnelAdapter` 的真实现：`NETunnelProviderManager`。
//  只做「读写系统隧道偏好、提交启动 / 停止、发应用消息、读当前状态」，
//  不持有任何生命周期决策（那是 `CoordinatorCore` 的事）。
//

import Foundation
import NetworkExtension

final class TunnelController: TunnelAdapter {

    private let lock = NSLock()
    private var manager: NETunnelProviderManager?
    private var handlers: [(TunnelStatus) -> Void] = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: nil, queue: nil
        ) { [weak self] note in
            guard let self, let connection = note.object as? NEVPNConnection else { return }
            self.lock.lock()
            let mine = self.manager?.connection
            let hs = self.handlers
            self.lock.unlock()
            // 只关心我们自己的隧道（系统里可能还有别的 VPN 偏好）。
            if let mine, mine !== connection { return }
            let status = Self.map(connection.status)
            hs.forEach { $0(status) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 启动时加载（不创建偏好，避免在没有连接意图时弹系统授权）

    /// 读取已有的隧道偏好（没有则保持为空）。完成后调用 `completion`（主线程之外的任意线程）。
    func loadExisting(completion: @escaping () -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            if let self, let first = managers?.first(where: { Self.isOurs($0) }) ?? managers?.first {
                self.lock.lock(); self.manager = first; self.lock.unlock()
            }
            completion()
        }
    }

    // MARK: - TunnelAdapter

    var currentStatus: TunnelStatus {
        lock.lock(); defer { lock.unlock() }
        guard let manager else { return .invalid }
        return Self.map(manager.connection.status)
    }

    func observeStatus(_ handler: @escaping (TunnelStatus) -> Void) {
        lock.lock(); handlers.append(handler); lock.unlock()
    }

    func ensureConfigured() throws {
        let m = try loadOrCreate()
        let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Bundle.main.tunnelProviderBundleIdentifier
        proto.serverAddress = "localhost"
        m.protocolConfiguration = proto
        m.localizedDescription = "ClashMiao"
        m.isEnabled = true
        // 不启用按需连接：否则「app 关」无法被系统尊重；同时清掉旧版本可能遗留的开关。
        m.isOnDemandEnabled = false
        m.onDemandRules = nil
        try await_ { m.saveToPreferences(completionHandler: $0) }
        try await_ { m.loadFromPreferences(completionHandler: $0) }
        lock.lock(); manager = m; lock.unlock()
    }

    func startTunnel() throws {
        guard let session = currentSession() else {
            throw TunnelAdapterError.failed("tunnel session unavailable")
        }
        do {
            try session.startTunnel(options: nil)
        } catch {
            throw TunnelAdapterError.failed(error.localizedDescription)
        }
    }

    func stopTunnel() {
        currentSession()?.stopTunnel()
    }

    func sendMessage(_ request: ExtensionRequest, timeout: TimeInterval) throws -> ExtensionReply {
        guard let session = currentSession() else {
            throw TunnelAdapterError.failed("tunnel session unavailable")
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(request)
        } catch {
            throw TunnelAdapterError.failed("cannot encode request")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var response: Data?
        var sendError: Error?
        do {
            try session.sendProviderMessage(data) { reply in
                response = reply
                semaphore.signal()
            }
        } catch {
            sendError = error
        }
        if let sendError { throw TunnelAdapterError.failed(sendError.localizedDescription) }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw TunnelAdapterError.failed("extension did not reply within \(Int(timeout)) s")
        }
        guard let response, let reply = try? JSONDecoder().decode(ExtensionReply.self, from: response) else {
            throw TunnelAdapterError.failed("malformed extension reply")
        }
        return reply
    }

    // MARK: - 内部

    private func currentSession() -> NETunnelProviderSession? {
        lock.lock(); defer { lock.unlock() }
        return manager?.connection as? NETunnelProviderSession
    }

    private func loadOrCreate() throws -> NETunnelProviderManager {
        var found: NETunnelProviderManager?
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            found = managers?.first(where: { Self.isOurs($0) }) ?? managers?.first
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw Self.wrap(loadError) }
        return found ?? NETunnelProviderManager()
    }

    /// 阻塞等一个带 completionHandler 的 NE 调用。
    private func await_(_ body: (@escaping (Error?) -> Void) -> Void) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var failure: Error?
        body { error in
            failure = error
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw Self.wrap(failure) }
    }

    private static func isOurs(_ m: NETunnelProviderManager) -> Bool {
        (m.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
            == Bundle.main.tunnelProviderBundleIdentifier
    }

    /// 用户拒绝系统「添加 VPN 配置」弹窗时，系统返回 `NEVPNErrorDomain` 的 `configurationReadWriteFailed`(5)。
    private static func wrap(_ error: Error) -> TunnelAdapterError {
        let ns = error as NSError
        if ns.domain == NEVPNErrorDomain, ns.code == NEVPNError.configurationReadWriteFailed.rawValue {
            return .permissionDenied(ns.localizedDescription)
        }
        return .failed(ns.localizedDescription)
    }

    static func map(_ status: NEVPNStatus) -> TunnelStatus {
        switch status {
        case .invalid: return .invalid
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .connected: return .connected
        case .reasserting: return .reasserting
        case .disconnecting: return .disconnecting
        @unknown default: return .disconnected
        }
    }
}
