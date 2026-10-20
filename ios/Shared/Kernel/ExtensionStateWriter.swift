//
//  ExtensionStateWriter.swift
//  ClashMiao (SingBoxPacketTunnel + tests)
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  扩展写 `extension-state.json` 的唯一入口。持锁、遵守**终态粘性**：
//  `failed` / `stopped` 一旦写下，随后的任何写（含内存采样、迟到的 running）都被丢弃，
//  所以失败记录不会被后面的 `stopped` 覆盖，也不会被旧采样“复活”。
//

import Foundation

public final class ExtensionStateWriter {
    public let sessionId: String
    private let url: URL
    private let lock = NSLock()
    private var state: ExtensionState

    public init(url: URL, sessionId: String = UUID().uuidString, launchId: String) {
        self.url = url
        self.sessionId = sessionId
        self.state = ExtensionState(sessionId: sessionId, launchId: launchId, phase: .starting, generation: 0)
        _ = flush()
    }

    public var current: ExtensionState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public var isTerminal: Bool {
        lock.lock(); defer { lock.unlock() }
        return Self.isTerminal(state.phase)
    }

    private static func isTerminal(_ p: ExtensionPhase) -> Bool { p == .failed || p == .stopped }

    /// 内核（再次）就绪：`generation` +1。终态之后无效，返回 false。
    @discardableResult
    public func markRunning(launchId: String, revision: Int64?) -> Bool {
        mutate { s in
            s.phase = .running
            s.launchId = launchId
            s.generation += 1
            s.revision = revision
            s.code = nil
            s.message = nil
        }
    }

    /// 重载进行中：回到 `starting`（`generation` 不变，直到新 service 真正起来）。
    @discardableResult
    public func markReloading(launchId: String) -> Bool {
        mutate { s in
            s.phase = .starting
            s.launchId = launchId
        }
    }

    @discardableResult
    public func markFailed(code: FailureCode, message: String) -> Bool {
        mutate { s in
            s.phase = .failed
            s.code = code
            s.message = message
        }
    }

    @discardableResult
    public func markStopped(reason: Int) -> Bool {
        mutate { s in
            s.phase = .stopped
            s.stopReason = reason
        }
    }

    /// 记录内存余量的历史最低值；只在更低时才写盘。
    @discardableResult
    public func noteAvailableMemory(_ bytes: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if Self.isTerminal(state.phase) { return false }
        if let min = state.availableMemoryMin, min <= bytes { return false }
        state.availableMemoryMin = bytes
        state.updatedAt = Date().timeIntervalSince1970
        return flushLocked()
    }

    // MARK: - 内部

    private func mutate(_ body: (inout ExtensionState) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if Self.isTerminal(state.phase) { return false }
        body(&state)
        state.updatedAt = Date().timeIntervalSince1970
        return flushLocked()
    }

    private func flush() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return flushLocked()
    }

    private func flushLocked() -> Bool {
        KernelFile.write(state, to: url)
    }
}
