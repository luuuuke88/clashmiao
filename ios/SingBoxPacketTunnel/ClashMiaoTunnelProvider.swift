//
//  ClashMiaoTunnelProvider.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  Info.plist 的 `NSExtensionPrincipalClass` 指向这个类。内核生命周期、应用消息与失败自洽
//  都在 `KernelProviderProxy` 里；这里不再有流量统计轮询（Runner 通过命令服务器取统计）。
//

import Foundation
import NetworkExtension

final class ClashMiaoTunnelProvider: KernelProviderProxy {}
