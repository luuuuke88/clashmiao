//
//  CoordinatorModel.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  进程级协调器的数据模型（连接生命周期 spec §2、§10；iOS 设计 §4）。
//  纯 Swift，不依赖 UIKit / NetworkExtension，`CoordinatorCore` 的单测直接使用。
//  所有 wire 字符串与 Dart `KernelSnapshot.fromJson`（lib/core/box_service/kernel_port.dart）逐字一致。
//

import Foundation

/// 内核状态。raw value 即线上小写字符串。
enum KernelStatus: String, Equatable {
    case stopped
    case starting
    case started
    case stopping
}

/// 谁设定了当前 desired。iOS 只有 App 内与系统（设置里的开关、按需连接、冷启动挂接）两类。
enum Source: String, Equatable {
    case app
    case system
}

/// `NEVPNStatus` 的镜像，核心不 import NetworkExtension。
enum TunnelStatus: Equatable {
    case invalid
    case disconnected
    case connecting
    case connected
    case reasserting
    case disconnecting

    /// 隧道已完全不存在。
    var isDown: Bool { self == .invalid || self == .disconnected }
}

struct KernelFailure: Equatable {
    let code: FailureCode
    let message: String
    let attempt: Int64
    /// 触发该失败的 Dart 请求序号；与 Dart 请求无关的失败为空。
    let seq: Int64?
}

/// 请求被拒绝的原因（线上值与 Dart `RequestRejection` 一致）。
enum RejectReason: String, Equatable {
    case stale
    case wrongEpoch
}

struct Receipt: Equatable {
    let accepted: Bool
    let reason: RejectReason?
    let epoch: String
    let appliedSeq: Int64
}

/// 权威快照。字段含义见 B spec §2；`version` 在纪元内单调，任何字段变化 +1。
struct KernelSnapshot: Equatable {
    var epoch: String
    var version: Int64
    var status: KernelStatus
    var attempt: Int64
    var desired: Desired
    var source: Source
    var appliedSeq: Int64
    var activeConfigRevision: Int64?
    var lastFailure: KernelFailure?
    var selectionsReplayNeeded: Bool
    /// 之后**可能还会读取**的运行时配置文件路径（去重、排序）；nil = 未知，Dart 一个都不删。
    var retainedConfigPaths: [String]?

    /// 事件通道 `com.clashmiao.app/kernel.snapshot` 的 JSON map 载荷。
    func toWireMap() -> [String: Any] {
        var map: [String: Any] = [
            "epoch": epoch,
            "version": version,
            "status": status.rawValue,
            "attempt": attempt,
            "desired": desired.rawValue,
            "source": source.rawValue,
            "appliedSeq": appliedSeq,
            "selectionsReplayNeeded": selectionsReplayNeeded,
            "activeConfigRevision": activeConfigRevision.map { $0 as Any } ?? NSNull(),
            "retainedConfigPaths": retainedConfigPaths.map { $0 as Any } ?? NSNull(),
        ]
        if let f = lastFailure {
            map["lastFailure"] = [
                "code": f.code.rawValue,
                "message": f.message,
                "attempt": f.attempt,
                "seq": f.seq.map { $0 as Any } ?? NSNull(),
            ] as [String: Any]
        } else {
            map["lastFailure"] = NSNull()
        }
        return map
    }

    /// 日志用的单行摘要：真机冒烟时据此核对 epoch/attempt/desired/source/version 序列。
    func logLine() -> String {
        var line = "epoch=\(epoch.prefix(8)) version=\(version) status=\(status.rawValue) " +
            "attempt=\(attempt) desired=\(desired.rawValue) source=\(source.rawValue) " +
            "appliedSeq=\(appliedSeq) rev=\(activeConfigRevision.map(String.init) ?? "nil") " +
            "replay=\(selectionsReplayNeeded) " +
            "retained=\(retainedConfigPaths.map { $0.map { ($0 as NSString).lastPathComponent }.description } ?? "unknown")"
        if let f = lastFailure {
            line += " failure=\(f.code.rawValue)(attempt=\(f.attempt),seq=\(f.seq.map(String.init) ?? "nil"))"
        }
        return line
    }
}

/// 执行层任务的结果（投递回命令层的事件载荷）。
enum JobResult: Equatable {
    /// `Connect`：已提交 `startVPNTunnel`。隧道真正就绪要等状态事件。
    case launched
    /// `Reload`：扩展回执成功，带新的 `(sessionId, generation)`。
    case reloaded(sessionId: String, generation: Int)
    /// `Teardown`：已提交 `stopVPNTunnel`。真正停止要等状态事件。
    case tornDown
    /// 被取消，没有产生任何需要回收的东西（取消点都在提交之前）。
    case cancelled
    case failed(FailureCode, String)
    /// `Connect`：`startVPNTunnel` 已提交，但系统迟迟没有让隧道可见地启动。执行层已补发 `stopVPNTunnel`；
    /// 核心把它当失败收口，并在一小段时间内不把迟到的 connecting / connected 当作外部启动（adoptGuard）。
    case abandoned(FailureCode, String)
}

enum TimerKind: String, Equatable {
    case startTimeout
    case watchdog
    case stopWatchdog
    case netDebounce
    case adoptGuard
}

/// 定时器标识。同一 `slot` 的定时器互相替换；触发时整个 key 原样回传 `onTimer`。
struct TimerKey: Hashable {
    let kind: TimerKind
    let subject: Int64
    let serial: Int64

    init(_ kind: TimerKind, subject: Int64 = 0, serial: Int64 = 0) {
        self.kind = kind
        self.subject = subject
        self.serial = serial
    }

    /// 同一 slot 的定时器互相替换。启动超时与看门狗按 subject（序列 / 任务 token）区分，
    /// 这样取消旧序列的定时器不会误伤新序列的。
    var slot: String {
        switch kind {
        case .startTimeout, .watchdog: return "\(kind.rawValue):\(subject)"
        case .stopWatchdog, .netDebounce, .adoptGuard: return kind.rawValue
        }
    }
}

/// 核心输出的动作，由 `KernelCoordinator` 在命令队列上按序执行。
enum Effect: Equatable {
    /// 执行层：拼配置 → 落盘意图 → `startVPNTunnel`。`reload` 为真走 `Reload`。
    case runConnect(token: Int64, spec: LaunchSpec, launchId: String)
    case runReload(token: Int64, spec: LaunchSpec, launchId: String, sessionId: String?)
    case runTeardown(token: Int64)
    /// 置位执行层任务的取消标（任务在下一个取消点看到）。
    case cancelJob(token: Int64)
    case setTimer(TimerKey, delayMs: Int64)
    case cancelTimer(TimerKey)
    /// 持久化当前 desired 与最近一次被受理的 LaunchSpec。
    case persist(desired: Desired, spec: LaunchSpec?, serial: Int64)
    case log(String)
}

/// 一次事件处理的产出：要执行的动作，以及（仅请求事件）回执。
struct CoreStep {
    let effects: [Effect]
    let receipt: Receipt?
}
