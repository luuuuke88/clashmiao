//
//  TunnelAdapter.swift
//  ClashMiao Runner
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  对 `NETunnelProviderManager` 的最小抽象。协调器的执行层只通过它碰系统隧道，
//  所以单测可以用假实现覆盖「授权被拒 / 启动失败 / 重载回执」等路径。
//

import Foundation

enum TunnelAdapterError: Error, Equatable {
    /// 用户拒绝了系统「添加 VPN 配置」弹窗，或偏好被禁用。
    case permissionDenied(String)
    case failed(String)

    var message: String {
        switch self {
        case .permissionDenied(let m), .failed(let m): return m
        }
    }
}

/// 全部方法在执行层的串行队列上调用，可以阻塞；`currentStatus` / `observeStatus` 线程安全。
protocol TunnelAdapter: AnyObject {
    /// 确保系统里存在并启用了本 App 的 VPN 偏好（首次会弹系统授权）。阻塞。
    func ensureConfigured() throws
    /// 提交 `startVPNTunnel`。只表示已提交；就绪要等状态事件。
    func startTunnel() throws
    /// 提交 `stopVPNTunnel`。
    func stopTunnel()
    /// 给扩展发应用消息（`reload` / `select`）并等回执。阻塞，超时抛错。
    func sendMessage(_ request: ExtensionRequest, timeout: TimeInterval) throws -> ExtensionReply

    var currentStatus: TunnelStatus { get }
    /// 订阅状态变化（任意线程回调）。先不推当前值，调用方自行 `currentStatus`。
    func observeStatus(_ handler: @escaping (TunnelStatus) -> Void)
}
