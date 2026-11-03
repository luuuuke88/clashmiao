//
//  KernelPlatformBridge.swift
//  ClashMiao SingBoxPacketTunnel
//
//  GPL-3.0 License
//  Copyright (c) 2026 ClashMiao Contributors
//
//  内核在扩展里的平台回调（`CorePlatform`）与命令服务器回调（`CoreEngineHandler`）。
//  TUN 规格到 NE 设置的翻译在 Shared/Kernel/TunSettings.swift（纯函数，有单测）。
//

import Darwin
import Foundation
import Libcore
import Network
import NetworkExtension

/// 一次隧道会话内的平台回调。
public final class KernelPlatformBridge: NSObject, CorePlatformProtocol, CoreEngineHandlerProtocol {

    /// 弱引用：provider 持有 bridge，反过来强持有会形成引用环。
    private weak var provider: KernelProviderProxy?

    /// 最近一次应用的 NE 设置：`clearDNSCache` 与系统代理开关要在它上面改。
    private let settingsLock = NSLock()
    private var lastAppliedSettings: NEPacketTunnelNetworkSettings?
    /// 设置代次：每次回收（重载 / 停止）+1。被打断的旧一轮迟到时，凭它认出自己已过期。
    private var settingsGeneration = 0
    /// 所有 NE 设置的提交（建 TUN、清 DNS 缓存、代理开关）串行经过这道门，并在提交前复核代次：
    /// 旧一轮不会排在新一轮之后生效，两步的「清空 → 恢复」也不会和别的提交交错。
    private let settingsGate = DispatchSemaphore(value: 1)

    private let monitorLock = NSLock()
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.clashmiao.tunnel.path-monitor")

    init(_ provider: KernelProviderProxy) {
        self.provider = provider
    }

    func discardCachedSettings() {
        settingsLock.lock()
        lastAppliedSettings = nil
        settingsGeneration += 1
        settingsLock.unlock()
    }

    private var appliedSettings: NEPacketTunnelNetworkSettings? {
        settingsLock.lock(); defer { settingsLock.unlock() }
        return lastAppliedSettings
    }

    private var currentGeneration: Int {
        settingsLock.lock(); defer { settingsLock.unlock() }
        return settingsGeneration
    }

    /// 在设置门内执行 `body`（阻塞调用线程：只在内核的回调线程上用，不在主线程）。
    /// `generation` 与当前代次不一致时不执行，返回 false。
    private func withSettingsGate(generation: Int, _ body: () throws -> Void) rethrows -> Bool {
        settingsGate.wait()
        defer { settingsGate.signal() }
        guard generation == currentGeneration else { return false }
        try body()
        return true
    }

    // MARK: - TUN

    /// 内核在启动流程里同步调用；`setTunnelNetworkSettings` 是异步的，这里阻塞等它完成。
    /// 被 Engine 取消时 Go 侧立即返回，这次设置仍会完成；NE 按调用顺序应用，新一轮总在其后生效。
    public func openTun(_ specJSON: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let ret0_ else { throw NSError(domain: "ClashMiaoTunnel", code: 2, userInfo: [NSLocalizedDescriptionKey: "nil return pointer"]) }
        guard let provider else { throw NSError(domain: "ClashMiaoTunnel", code: 7, userInfo: [NSLocalizedDescriptionKey: "provider released"]) }
        let spec: TunSpec
        do {
            spec = try JSONDecoder().decode(TunSpec.self, from: Data((specJSON ?? "").utf8))
        } catch {
            throw TunSpecError.malformed(error.localizedDescription)
        }
        let ignored = TunSettingsBuilder.ignoredFields(spec)
        if !ignored.isEmpty {
            provider.forwardKernelLine("[Tunnel] tun spec fields ignored on iOS: \(ignored.joined(separator: ","))")
        }
        let settings = try TunSettingsBuilder.settings(from: spec)
        let generation = currentGeneration
        let applied = try withSettingsGate(generation: generation) {
            try awaitBlockingThrowing { [provider] in
                try await provider.setTunnelNetworkSettings(settings)
            }
            settingsLock.lock()
            if settingsGeneration == generation { lastAppliedSettings = settings }
            settingsLock.unlock()
        }
        guard applied else {
            throw NSError(domain: "ClashMiaoTunnel", code: 8, userInfo: [NSLocalizedDescriptionKey: "tunnel session moved on; stale tun request dropped"])
        }
        // fd 归 NE：内核 dup 一份并在服务关闭时关自己那份，这一份我们不关。
        let fd = CoreTunnelFileDescriptor()
        guard fd >= 0 else {
            throw NSError(domain: "ClashMiaoTunnel", code: 3, userInfo: [NSLocalizedDescriptionKey: "missing tun file descriptor"])
        }
        ret0_.pointee = fd
    }

    /// 扩展自己的 socket 本来就不走隧道，不需要保护。
    public func protect(_ fd: Int32) throws {}

    public func useProcFS() -> Bool { false }

    public func findOwner(_ protocol: Int32, srcAddr: String?, srcPort: Int32,
                          dstAddr: String?, dstPort: Int32, error: NSErrorPointer) -> String {
        error?.pointee = NSError(domain: "ClashMiaoTunnel", code: 5,
                                 userInfo: [NSLocalizedDescriptionKey: "connection owner lookup is not supported on iOS"])
        return ""
    }

    // MARK: - 默认接口监视

    public func startInterfaceMonitor(_ l: CoreInterfaceListenerProtocol?) throws {
        guard let l else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            // 排除隧道自己的 utun：默认接口指的是物理出口。
            let iface = path.availableInterfaces.first { !$0.name.hasPrefix("utun") && $0.type != .loopback }
            guard path.status == .satisfied, let iface else {
                l.update("", index: -1, expensive: false, constrained: false)
                return
            }
            l.update(iface.name, index: Int32(iface.index), expensive: path.isExpensive, constrained: path.isConstrained)
        }
        monitorLock.lock()
        pathMonitor?.cancel()
        pathMonitor = monitor
        monitorLock.unlock()
        monitor.start(queue: monitorQueue)
    }

    public func stopInterfaceMonitor() throws {
        monitorLock.lock()
        pathMonitor?.cancel()
        pathMonitor = nil
        monitorLock.unlock()
    }

    // MARK: - 接口列表

    /// `[{name,index,mtu,flags,type,addresses[],dns[],gateway[],metered}]`；type：0 wifi、1 蜂窝、2 有线、3 其它。
    public func interfacesJSON(_ error: NSErrorPointer) -> String {
        monitorLock.lock()
        let path = pathMonitor?.currentPath
        monitorLock.unlock()
        var types: [String: Int32] = [:]
        for iface in path?.availableInterfaces ?? [] {
            switch iface.type {
            case .wifi: types[iface.name] = 0
            case .cellular: types[iface.name] = 1
            case .wiredEthernet: types[iface.name] = 2
            default: types[iface.name] = 3
            }
        }
        let list = Self.collectInterfaces(types: types)
        do {
            let data = try JSONSerialization.data(withJSONObject: list)
            return String(decoding: data, as: UTF8.self)
        } catch let e as NSError {
            error?.pointee = e
            return ""
        }
    }

    /// `types`：系统路径给出的接口类型（监视器在跑时才有）；缺省按名字推断（iPhone 上 en0 是 Wi-Fi、pdp_ip 是蜂窝）。
    static func collectInterfaces(types: [String: Int32]) -> [[String: Any]] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        struct Entry { var flags: Int32; var mtu: Int32; var addrs: [String] }
        var byName: [String: Entry] = [:]
        var order: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            // 隧道自己的 utun 与回环不是出口
            if name.hasPrefix("utun") || name.hasPrefix("lo") { continue }
            if byName[name] == nil {
                byName[name] = Entry(flags: Int32(bitPattern: p.pointee.ifa_flags), mtu: 0, addrs: [])
                order.append(name)
            }
            guard let sa = p.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            if family == AF_LINK, let data = p.pointee.ifa_data {
                byName[name]?.mtu = Int32(bitPattern: data.assumingMemoryBound(to: if_data.self).pointee.ifi_mtu)
                continue
            }
            guard family == AF_INET || family == AF_INET6, let mask = p.pointee.ifa_netmask else { continue }
            if let addr = numericHost(sa) {
                byName[name]?.addrs.append("\(addr)/\(prefixLength(mask, family: family))")
            }
        }
        return order.compactMap { name -> [String: Any]? in
            guard let e = byName[name], !e.addrs.isEmpty else { return nil }
            let type = types[name] ?? (name == "en0" ? 0 : (name.hasPrefix("pdp_ip") ? 1 : (name.hasPrefix("en") ? 2 : 3)))
            return [
                "name": name, "index": Int32(if_nametoindex(name)), "mtu": e.mtu > 0 ? e.mtu : 1500,
                "flags": e.flags, "type": type, "addresses": e.addrs,
                "dns": [String](), "gateway": [String](), "metered": type == 1,
            ]
        }
    }

    private static func numericHost(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(sa.pointee.sa_family == AF_INET6 ? MemoryLayout<sockaddr_in6>.size : MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let s = String(cString: host)
        // 链路本地地址带 %scope 后缀，内核不认
        return s.split(separator: "%").first.map(String.init)
    }

    private static func prefixLength(_ mask: UnsafeMutablePointer<sockaddr>, family: Int32) -> Int {
        var bits = 0
        if family == AF_INET {
            mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                bits = UInt32(bigEndian: $0.pointee.sin_addr.s_addr).nonzeroBitCount
            }
        } else {
            mask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                var a = $0.pointee.sin6_addr
                withUnsafeBytes(of: &a) { raw in bits = raw.reduce(0) { $0 + $1.nonzeroBitCount } }
            }
        }
        return bits
    }

    // MARK: - DNS / 日志

    public func clearDNSCache() {
        guard let provider else { return }
        let generation = currentGeneration
        // 重设一次隧道设置让系统丢掉 DNS 缓存；期间声明 reasserting，系统不会因此断开隧道。
        // 两步在设置门内连续完成，并且只恢复本代的设置：重载 / 停止不会被旧设置覆盖回去。
        _ = withSettingsGate(generation: generation) {
            guard let settings = appliedSettings else { return }
            provider.reasserting = true
            defer { provider.reasserting = false }
            do {
                try awaitBlockingThrowing { try await provider.setTunnelNetworkSettings(nil) }
                try awaitBlockingThrowing { try await provider.setTunnelNetworkSettings(settings) }
            } catch {
                provider.forwardKernelLine("[Tunnel] clearing DNS cache failed: \(error.localizedDescription)")
            }
        }
    }

    /// nil：用内核自己的本地 DNS（扩展里直接走系统网络）。
    public func localDNS() -> CoreLocalDNSProtocol? { nil }

    /// 内核日志已经在命令服务器的日志流里（Runner 订阅它）；这里不再转写，避免同一行进两次。
    public func writeLog(_ line: String?) {}

    // MARK: - CoreEngineHandler

    /// 不阻塞内核的回调线程：只入队，由 provider 的串行队列执行重载。
    public func onReloadRequested() {
        provider?.requestSelfReload()
    }

    public func onStopRequested() {
        provider?.cancelTunnelWithError(nil)
    }

    public func systemProxyAvailable() -> Bool {
        appliedSettings?.proxySettings?.httpServer != nil
    }

    public func systemProxyEnabled() -> Bool {
        guard let proxy = appliedSettings?.proxySettings, proxy.httpServer != nil else { return false }
        return proxy.httpEnabled
    }

    public func setSystemProxyEnabled(_ enabled: Bool) {
        guard let provider else { return }
        let generation = currentGeneration
        // 在设置门内修改并提交本代的设置，不与建 TUN / 清缓存交错。
        _ = withSettingsGate(generation: generation) {
            guard
                let settings = appliedSettings,
                let proxy = settings.proxySettings,
                proxy.httpServer != nil,
                proxy.httpEnabled != enabled
            else { return }
            proxy.httpEnabled = enabled
            proxy.httpsEnabled = enabled
            settings.proxySettings = proxy
            do {
                try awaitBlockingThrowing { try await provider.setTunnelNetworkSettings(settings) }
            } catch {
                provider.forwardKernelLine("[Tunnel] toggling system proxy failed: \(error.localizedDescription)")
            }
        }
    }
}
