//
//  ExtensionState.swift
//  ClashMiao (Runner + SingBoxPacketTunnel)
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Runner 与扩展之间的落盘契约之二：`extension-state.json`（扩展唯一写者，Runner 只读），
//  以及两个进程之间的应用消息（`sendProviderMessage`）格式。
//

import Foundation

/// 扩展对自己所处阶段的如实记录。`failed` 与 `stopped` 对同一 `sessionId` 是终态（写入器丢弃随后的任何写）。
///
/// 被系统强杀（内存超限）时扩展没有任何回调可写，所以状态会停在 `running` / `starting` 而隧道已
/// `disconnected`——Runner 据此判定内核意外退出（见 `CoordinatorCore`）。
public enum ExtensionPhase: String, Codable, Equatable {
    case starting
    case running
    case stopped
    case failed
}

public struct ExtensionState: Codable, Equatable {
    /// 扩展实例 ID：每次 `startTunnel` 新生成。系统启动、扩展被杀后重启都会换新。
    public var sessionId: String
    /// 产生当前 service 的 Runner 操作 ID（`KernelIntent.launchId`）。
    public var launchId: String
    public var phase: ExtensionPhase
    /// 内核 service 代次：扩展内每创建一次 service +1（首次启动 =1）。`clearDNSCache` 引起的 `reasserting` 不改变它。
    public var generation: Int
    /// 正在运行的配置的 revision（`phase == .running` 时有值）。
    public var revision: Int64?
    /// `phase == .failed` 时的失败码与信息。
    public var code: FailureCode?
    public var message: String?
    /// `phase == .stopped` 时的 `NEProviderStopReason.rawValue`。
    public var stopReason: Int?
    /// 扩展内内存余量（`os_proc_available_memory()`）的历史最低值（字节），诊断用；未采样为 nil。
    public var availableMemoryMin: Int64?
    /// 进程 `phys_footprint` 的历史最高值（字节），诊断用。
    public var footprintMax: Int64?
    public var updatedAt: Double

    public init(
        sessionId: String = "session-0",
        launchId: String,
        phase: ExtensionPhase,
        generation: Int = 1,
        revision: Int64? = nil,
        code: FailureCode? = nil,
        message: String? = nil,
        stopReason: Int? = nil,
        availableMemoryMin: Int64? = nil,
        footprintMax: Int64? = nil,
        updatedAt: Double = Date().timeIntervalSince1970
    ) {
        self.sessionId = sessionId
        self.launchId = launchId
        self.phase = phase
        self.generation = generation
        self.revision = revision
        self.code = code
        self.message = message
        self.stopReason = stopReason
        self.availableMemoryMin = availableMemoryMin
        self.footprintMax = footprintMax
        self.updatedAt = updatedAt
    }
}

/// `NEProviderStopReason` 的归类。未知值（新系统版本新增）按「系统 / 用户关闭」处理，不当作失败。
public enum StopReasonClass {
    /// providerFailed(2) / configurationFailed(7) / connectionFailed(14)：这是故障，不是主动关闭。
    public static func isFailure(_ rawValue: Int?) -> Bool {
        guard let rawValue else { return false }
        return rawValue == 2 || rawValue == 7 || rawValue == 14
    }
}

// MARK: - 应用消息（Runner → 扩展）

/// `sendProviderMessage` 的请求。JSON 编码，`op` 区分种类。
public struct ExtensionRequest: Codable, Equatable {
    public enum Op: String, Codable {
        case reload
        case select
    }

    public var op: Op
    /// `reload`：目标操作 ID，必须等于扩展此刻读到的 `intent.launchId`（过期消息被拒绝）。
    public var launchId: String?
    /// `select`：手选出站，并带上 Runner 以为的运行实例 `(sessionId, generation)`，扩展在 service 替换的同一条
    /// 串行队列上比对，不符则 `stale` 且不写入。
    public var group: String?
    public var outbound: String?
    public var sessionId: String?
    public var generation: Int?

    public init(
        op: Op, launchId: String? = nil, group: String? = nil, outbound: String? = nil,
        sessionId: String? = nil, generation: Int? = nil
    ) {
        self.op = op
        self.launchId = launchId
        self.group = group
        self.outbound = outbound
        self.sessionId = sessionId
        self.generation = generation
    }
}

/// 扩展对应用消息的回执（JSON）。`code == nil && !ok` 之外，`stale` 用字符串 `"stale"` 表示。
public struct ExtensionReply: Codable, Equatable {
    public static let staleCode = "stale"

    public var ok: Bool
    /// 失败码（`FailureCode.rawValue`）或 `"stale"`。
    public var code: String?
    public var message: String?
    /// `reload` 成功后的新实例标识。
    public var sessionId: String?
    public var generation: Int?

    public init(ok: Bool, code: String? = nil, message: String? = nil, sessionId: String? = nil, generation: Int? = nil) {
        self.ok = ok
        self.code = code
        self.message = message
        self.sessionId = sessionId
        self.generation = generation
    }

    public var failureCode: FailureCode? { code.flatMap(FailureCode.init(rawValue:)) }
    public var isStale: Bool { code == Self.staleCode }
}
