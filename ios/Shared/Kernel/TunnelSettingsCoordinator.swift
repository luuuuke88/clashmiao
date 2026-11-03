//
//  TunnelSettingsCoordinator.swift
//  ClashMiao
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  扩展里 NE 隧道设置的唯一提交通道（建 TUN、清 DNS 缓存、系统代理开关），以及 `reasserting` 的唯一持有者。
//
//  - 所有提交串行经过一道门；「复核本代是否仍有效」与「向 NE 发起调用」在同一把锁内完成，
//    `stop()` 也取这把锁：停止之后不会再有新的提交到达 NE。
//  - 每一次等待都有上限（等门、等 NE 回调）；`stop()` 立即放行所有在途的等待，NE 迟到的回调被丢弃。
//  - NE 在时限内不回调、或清缓存后恢复失败 = 隧道设置失控：协调器进入终态（之后不再提交，
//    所以不会有两个 NE 调用重叠、也不依赖它们的生效顺序），可选操作再请 provider 以失败收掉隧道。
//  - `reasserting` 按持有计数：清 DNS 与重载各持一份，最后一个释放的人才把它放回 false。
//

import Foundation
import NetworkExtension

/// 协调器只经它接触 NE：真实实现是 packet tunnel provider，单测里是假的提交器。
protocol TunnelSettingsHost: AnyObject {
    /// 发起一次设置提交并立即返回；`completion` 在 NE 完成时（任意线程）调用一次。
    func submitTunnelSettings(_ settings: NEPacketTunnelNetworkSettings?, completion: @escaping (Error?) -> Void)
    func setReasserting(_ on: Bool)
    /// 隧道设置失控（NE 不回调，或清缓存后恢复失败）：隧道不能再按缓存的设置继续跑，由 provider 以失败收掉。
    func tunnelSettingsLost(_ reason: String)
}

enum TunnelSettingsError: Error, Equatable {
    /// 本代已被回收（重载 / 停止），请求被丢弃。
    case stale
    /// 等不到设置门。
    case busy
    /// NE 在时限内没有回调（协调器随之进入终态）。
    case timedOut
}

final class TunnelSettingsCoordinator {

    /// 建 TUN 的时限：等门 + 等 NE 回调各自不超过它。可选操作（清缓存、代理开关）用 `optionalTimeout`。
    private let tunTimeout: TimeInterval
    private let optionalTimeout: TimeInterval

    private let lock = NSLock()
    private weak var host: TunnelSettingsHost?
    private var generation = 0
    private var stopped = false
    private var applied: NEPacketTunnelNetworkSettings?
    private var reassertHolds = 0
    /// 失败的重载要求保持 reasserting 直到隧道被取消：粘性，与谁最后释放无关。
    private var reassertPinned = false
    private var inFlight: [ObjectIdentifier: PendingCall] = [:]

    private let gate = DispatchSemaphore(value: 1)

    init(tunTimeout: TimeInterval = 30, optionalTimeout: TimeInterval = 10) {
        self.tunTimeout = tunTimeout
        self.optionalTimeout = optionalTimeout
    }

    func attach(_ host: TunnelSettingsHost) {
        lock.lock(); self.host = host; lock.unlock()
    }

    // MARK: - 代次与停止

    /// 当前代次；请求在发起时取一次，提交前凭它复核。
    var currentGeneration: Int {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// 本代最近一次成功提交的设置。
    var appliedSettings: NEPacketTunnelNetworkSettings? {
        lock.lock(); defer { lock.unlock() }
        return applied
    }

    /// 回收本代（重载 / 停止服务时）：丢掉缓存，之前取到的代次全部过期。
    func discard() {
        lock.lock()
        applied = nil
        generation += 1
        lock.unlock()
    }

    /// 终态：之后的提交一律过期；在途等待立即以 `.stale` 返回，NE 迟到的回调被丢弃。
    /// 此后也不再动 `reasserting`（系统正在拆隧道）。
    func stop() {
        lock.lock()
        let pending = enterTerminalLocked()
        lock.unlock()
        pending.forEach { $0.finish(.abandoned) }
    }

    private func enterTerminalLocked() -> [PendingCall] {
        stopped = true
        applied = nil
        generation += 1
        return Array(inFlight.values)
    }

    /// 设置失控：进入终态（同 `stop()`），`notify` 时请 provider 收掉隧道。只在持门时调用。
    private func lose(_ reason: String, notify: Bool) {
        lock.lock()
        let first = !stopped
        let pending = first ? enterTerminalLocked() : []
        let host = self.host
        lock.unlock()
        pending.forEach { $0.finish(.abandoned) }
        if first, notify { host?.tunnelSettingsLost(reason) }
    }

    // MARK: - reasserting

    func beginReasserting() {
        lock.lock(); defer { lock.unlock() }
        reassertHolds += 1
        if reassertHolds == 1, !stopped { host?.setReasserting(true) }
    }

    /// `leaveSet`：失败路径马上要取消隧道，此后 reasserting 一直保持（别的持有者后释放也不放回）。
    func endReasserting(leaveSet: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if leaveSet { reassertPinned = true }
        reassertHolds = max(0, reassertHolds - 1)
        if reassertHolds == 0, !stopped, !reassertPinned { host?.setReasserting(false) }
    }

    // MARK: - 三类提交

    /// 建 TUN：提交本代的完整设置并记为已应用。失败、过期、超时都抛错（内核启动随之失败，
    /// 启动 / 重载的失败路径会收掉隧道，所以这里超时不另行通知）。
    func applyTunSettings(_ settings: NEPacketTunnelNetworkSettings, generation: Int) throws {
        try withGate(timeout: tunTimeout) {
            let result = submit(settings, generation: generation, timeout: tunTimeout)
            if case .failure(TunnelSettingsError.timedOut) = result {
                lose("NE did not answer the tun settings within \(Int(tunTimeout)) s", notify: false)
            }
            try result.get()
            record(settings, generation: generation)
        }
    }

    /// 重设一次隧道设置让系统丢掉 DNS 缓存（期间持有 reasserting）。返回失败原因，nil 为成功。
    @discardableResult
    func clearDNSCache() -> Error? {
        let gen = currentGeneration
        do {
            try withGate(timeout: optionalTimeout) {
                guard let settings = appliedIfCurrent(gen) else { throw TunnelSettingsError.stale }
                beginReasserting()
                defer { endReasserting() }
                switch submit(nil, generation: gen, timeout: optionalTimeout) {
                case .success:
                    break
                case .failure(TunnelSettingsError.timedOut):
                    lose("NE did not answer clearing the tunnel settings", notify: true)
                    throw TunnelSettingsError.timedOut
                case .failure(let error):
                    throw error // 过期，或 NE 明确拒绝（设置没变，不需要恢复）
                }
                // 已清空：恢复失败（含超时）时隧道停在没有设置的状态，不能继续跑；过期则由新一代提交自己的设置。
                if case .failure(let error) = submit(settings, generation: gen, timeout: optionalTimeout) {
                    if error as? TunnelSettingsError != .stale {
                        lose("restoring tunnel settings after clearing DNS cache failed: \(error.localizedDescription)", notify: true)
                    }
                    throw error
                }
            }
            return nil
        } catch {
            return error
        }
    }

    /// 系统代理开关：改副本、提交成功后才替换缓存（NE 明确拒绝时缓存仍与系统实际生效的一致；
    /// NE 不回调则设置失控，收掉隧道，不留一个结局不明的缓存）。返回 nil 表示成功或无需改动。
    @discardableResult
    func setSystemProxyEnabled(_ enabled: Bool) -> Error? {
        let gen = currentGeneration
        do {
            try withGate(timeout: optionalTimeout) {
                guard isCurrent(gen) else { throw TunnelSettingsError.stale }
                guard
                    let current = appliedIfCurrent(gen),
                    let currentProxy = current.proxySettings,
                    currentProxy.httpServer != nil,
                    currentProxy.httpEnabled != enabled,
                    let settings = current.copy() as? NEPacketTunnelNetworkSettings,
                    let proxy = currentProxy.copy() as? NEProxySettings
                else { return }
                proxy.httpEnabled = enabled
                proxy.httpsEnabled = enabled
                settings.proxySettings = proxy
                let result = submit(settings, generation: gen, timeout: optionalTimeout)
                if case .failure(TunnelSettingsError.timedOut) = result {
                    lose("NE did not answer the system proxy change", notify: true)
                }
                try result.get()
                record(settings, generation: gen)
            }
            return nil
        } catch {
            return error
        }
    }

    // MARK: - 内部

    private func withGate(timeout: TimeInterval, _ body: () throws -> Void) throws {
        guard gate.wait(timeout: .now() + timeout) == .success else { throw TunnelSettingsError.busy }
        defer { gate.signal() }
        try body()
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return gen == generation && !stopped
    }

    private func appliedIfCurrent(_ gen: Int) -> NEPacketTunnelNetworkSettings? {
        lock.lock(); defer { lock.unlock() }
        return gen == generation && !stopped ? applied : nil
    }

    private func record(_ settings: NEPacketTunnelNetworkSettings, generation gen: Int) {
        lock.lock()
        if gen == generation, !stopped { applied = settings }
        lock.unlock()
    }

    /// 复核与发起在同一把锁内：`stop()` / `discard()` 要么排在发起之前（于是这里返回 stale），
    /// 要么排在之后（于是它放行这次等待）。之后最多等 `timeout`。
    private func submit(_ settings: NEPacketTunnelNetworkSettings?, generation gen: Int,
                        timeout: TimeInterval) -> Result<Void, Error> {
        let call = PendingCall()
        let key = ObjectIdentifier(call)
        lock.lock()
        guard gen == generation, !stopped, let host else {
            lock.unlock()
            return .failure(TunnelSettingsError.stale)
        }
        inFlight[key] = call
        host.submitTunnelSettings(settings) { error in call.finish(.completed(error)) }
        lock.unlock()

        let outcome = call.wait(timeout: timeout)
        lock.lock(); inFlight[key] = nil; lock.unlock()
        switch outcome {
        case .completed(nil): return .success(())
        case .completed(let error?): return .failure(error)
        case .abandoned: return .failure(TunnelSettingsError.stale)
        case nil: return .failure(TunnelSettingsError.timedOut) // 每个调用方据此进入终态
        }
    }
}

/// 一次在途提交：NE 回调、`stop()`、超时三者先到者定结果。
private final class PendingCall {
    enum Outcome { case completed(Error?), abandoned }

    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var outcome: Outcome?

    func finish(_ o: Outcome) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = o
        lock.unlock()
        done.signal()
    }

    /// nil = 超时。
    func wait(timeout: TimeInterval) -> Outcome? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return outcome
    }
}
